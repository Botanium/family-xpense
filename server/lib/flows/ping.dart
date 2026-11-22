/// `ping`: the sample flow behind the context provider.
///
/// It proves the route, the provider and the context plumbing end to end
/// without calling a model or spending quota. Served at `POST /v1/ping`.
library;

import 'package:genkit/genkit.dart';

import 'package:xpense_agent/auth/xpense_context.dart';

/// Defines the `ping` flow on [ai].
///
/// Input: an optional string, echoed back. Output: `{status: "ok", echo?,
/// uid, hid, locale, privacyMode, tz}`, read only from the verified context.
Flow<String?, Map<String, String>, void, void> definePingFlow(Genkit ai) =>
    ai.defineFlow(
      name: 'ping',
      inputSchema: .nullable(.string(maxLength: 200)),
      outputSchema: .map(.string(), .string()),
      fn: (input, ctx) async {
        final context = XpenseContext.of(ctx.context);
        return {
          'status': 'ok',
          'echo': ?input,
          ...context.toMap().map((k, v) => MapEntry(k, v.toString())),
        };
      },
    );
