import threading
import queue
import numpy as np
import pygame


class AudioOutput:
    """Background audio output using pygame.mixer.

    This class accepts int16 mono numpy arrays and plays them via pygame.
    It's designed for testing; a production implementation should use a
    lower-level audio callback or a ring buffer shared with SDL.
    """
    def __init__(self, sample_rate=44100, chunk_size=1024, max_queue=16):
        self.sample_rate = sample_rate
        self.chunk_size = chunk_size
        self._partial = np.zeros((0,), dtype=np.int16)
        self._q = queue.Queue(maxsize=max_queue)
        self._stop = threading.Event()

        # Initialize mixer if not already
        try:
            pygame.mixer.init(frequency=self.sample_rate, size=-16, channels=1, buffer=self.chunk_size)
        except Exception:
            # If already initialized or fails, ignore; hope it's usable
            pass

        # Determine actual mixer configuration (some backends force stereo)
        try:
            init = pygame.mixer.get_init()
            if init is None:
                self.channels = 1
            else:
                # init -> (freq, size, channels)
                self.channels = init[2]
        except Exception:
            self.channels = 1

        self._channel = pygame.mixer.Channel(0)
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def _prepare_pcm(self, pcm: np.ndarray) -> np.ndarray:
        if pcm.dtype != np.int16:
            pcm = pcm.astype(np.int16)

        if self.channels == 2:
            if pcm.ndim == 1:
                pcm = np.stack([pcm, pcm], axis=1)
            elif pcm.ndim == 2 and pcm.shape[1] == 1:
                pcm = np.repeat(pcm, 2, axis=1)
        else:
            if pcm.ndim == 2 and pcm.shape[1] == 2:
                pcm = pcm[:, 0]
        return pcm

    def enqueue(self, pcm_int16: np.ndarray):
        """Enqueue a single numpy int16 array (mono or stereo) for playback."""
        try:
            pcm = pcm_int16.copy()
            pcm = self._prepare_pcm(pcm)

            if pcm.ndim == 1:
                self._partial = np.concatenate((self._partial, pcm))
                while len(self._partial) >= self.chunk_size:
                    chunk = self._partial[:self.chunk_size]
                    self._partial = self._partial[self.chunk_size:]
                    self._q.put_nowait(chunk)
            else:
                # Stereo chunk handling
                if pcm.shape[0] >= self.chunk_size:
                    for start in range(0, pcm.shape[0], self.chunk_size):
                        end = min(start + self.chunk_size, pcm.shape[0])
                        self._q.put_nowait(pcm[start:end])
                else:
                    self._q.put_nowait(pcm)
        except queue.Full:
            # Drop if queue full
            pass

    def enqueue_tone(self, frequency=440.0, duration=0.4, volume=0.5):
        """Generate and enqueue a mono test tone for a short duration."""
        num_samples = int(self.sample_rate * duration)
        t = np.linspace(0.0, duration, num_samples, endpoint=False)
        tone = np.sin(2.0 * np.pi * frequency * t) * volume
        pcm = (tone * 32767.0).astype(np.int16)
        for start in range(0, len(pcm), self.chunk_size):
            self.enqueue(pcm[start:start + self.chunk_size])

    def play_test_tone(self, frequency=440.0, duration=0.4, volume=0.5):
        """Play a short test tone to verify the audio output pipeline."""
        self.enqueue_tone(frequency=frequency, duration=duration, volume=volume)

    def _run(self):
        while not self._stop.is_set():
            try:
                pcm = self._q.get(timeout=0.01)
            except queue.Empty:
                continue
            try:
                sound = pygame.sndarray.make_sound(pcm)
                if not self._channel.get_busy():
                    self._channel.play(sound)
                else:
                    try:
                        self._channel.queue(sound)
                    except Exception:
                        pass
            except Exception:
                continue

    def stop(self):
        self._stop.set()
        try:
            self._thread.join(timeout=0.5)
        except Exception:
            pass
        try:
            pygame.mixer.quit()
        except Exception:
            pass
