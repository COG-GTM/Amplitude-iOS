# Amplitude Demo

Build and launch the SwiftUI demo on the booted iPhone 17 simulator:

```sh
AMPLITUDE_API_KEY=<client-side-key> ./run.sh --reset
```

The optional `--reset` uninstalls the app first to start with a clean SDK database. The API key is read from the `AMPLITUDE_API_KEY` environment variable and passed to the simulator process; it is never stored in the project.
