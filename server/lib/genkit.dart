/// The Genkit instance for the service (ARCHITECTURE 4.3).
library;

import 'package:genkit/genkit.dart';
import 'package:genkit_a2ui/a2ui.dart';
import 'package:genkit_google_genai/genkit_google_genai.dart';

/// Creates the Genkit instance.
///
/// `googleAI()` is registered only with a Gemini key ([withGoogleAI]); the
/// key comes from Secret Manager as `GEMINI_API_KEY` (ARCHITECTURE 4.4).
/// Without it the service still starts and serves the routes that need no
/// model, which is how it runs locally and in tests. `A2uiPlugin()` registers
/// the `a2ui` middleware the agent resolves by name. Model ids are read from
/// `config/runtime`, never hard-coded here (D-04).
///
/// Telemetry must be configured before this is called.
Genkit createGenkit({required bool withGoogleAI}) =>
    Genkit(plugins: [if (withGoogleAI) googleAI(), A2uiPlugin()]);
