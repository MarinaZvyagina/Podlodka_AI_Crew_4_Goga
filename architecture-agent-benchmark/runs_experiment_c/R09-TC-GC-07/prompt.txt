## Ticket: A/B test an alternative speech-to-text pipeline for voice search

The voice search feature (the microphone button that lets a user dictate a
search query) currently always transcribes speech using the same pipeline
under the hood.

We want to run an internal experiment to compare transcription quality and
latency against an alternative speech-to-text pipeline. A portion of users
enrolled in the experiment should have their voice search transcribed using
the alternative pipeline, while everyone else keeps using today's default
pipeline, selected behind a simple flag we can flip for testing.

Requirements:

- From the end user's point of view, nothing about the feature should look
  or behave differently: the record button, the streaming of partial
  results while speaking, error handling (e.g. permission denied, no speech
  detected), and stopping/cancelling a recording must all keep working
  exactly as they do today, regardless of which pipeline is active.
- Enrolled vs. non-enrolled users should be able to run side by side without
  interfering with each other (e.g. no shared mutable state that would leak
  between them).
- The alternative pipeline can be a reasonable stand-in/mock implementation
  for now — the goal of this ticket is the wiring and the ability to flip
  between the two, not sourcing a production-grade third-party engine.
- Please add tests covering that both pipelines can be selected and that the
  rest of the feature behaves identically either way.
