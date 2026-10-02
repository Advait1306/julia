Run the speech regression checks on Apple Silicon with Xcode 27:

```sh
bash tests/run-sst-smoke.sh
```

This builds Julia and checks right-Command holds, duplicate events, left/right
Command combinations, shortcut cancellation, early release, empty transcripts,
failures, copied audio buffers, queue overflow, and draining on release.
It uses an injected command handler and never changes system settings.

For real streaming inference, first download the model in Julia, then use the
public JFK sample (the test checks its final word):

```sh
curl -L https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/samples/jfk.wav -o /tmp/julia-sst-jfk.wav
bash tests/run-sst-smoke.sh /tmp/julia-sst-jfk.wav
```

If `JEV_API_KEY` is present in the environment, the fixture's final transcript
also goes through the coordinator to the real Jev API. The returned decision
must preserve settings; the test never applies it. Live microphone capture and
global keyboard delivery require their macOS permissions and manual testing.
