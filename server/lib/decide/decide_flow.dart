/// `decide`: the Decisions proxy flow, served at `POST /v1/decide` behind the
/// context provider (metered on `decisions`).
///
/// Input is the phone's `DecideRequest`; output is `DecideResponse`. The
/// household, the speaker and the time zone come only from the verified
/// context, and the options only from the household's own data, so the
/// phone cannot inject options or ask about another household.
library;

import 'package:genkit/genkit.dart';
import 'package:xpense_agent/auth/xpense_context.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The longest message classified; longer ones are refused with 400.
const int maxDecideTextLength = 2000;

/// The languages the Decisions path is used in (D-36: English only).
const Set<String> decideLanguages = {'en'};

/// The flow's type.
typedef DecideFlow = Flow<DecideRequest, DecideResponse, void, void>;

/// Defines the `decide` flow on [ai] over [classifier].
DecideFlow defineDecideFlow(Genkit ai, EntryClassifier classifier) =>
    ai.defineFlow(
      name: 'decide',
      inputSchema: DecideRequest.$schema,
      outputSchema: DecideResponse.$schema,
      fn: (request, ctx) async {
        final context = XpenseContext.of(ctx.context);
        final text = request.text.trim();
        if (text.isEmpty || text.length > maxDecideTextLength) {
          throw GenkitException(
            'invalid_text',
            status: StatusCode.invalidArgument,
          );
        }
        final ask = <DecideQuestion>{};
        for (final key in request.ask) {
          final q = DecideQuestion.byKey(key);
          if (q == null) {
            throw GenkitException(
              'unknown_question',
              status: StatusCode.invalidArgument,
            );
          }
          ask.add(q);
        }
        if (!decideLanguages.contains(request.lang)) {
          // Not refused: the phone classifies on its own, as for an outage.
          return DecideResponse(unavailable: true);
        }
        return await classifier.classify(
          context: context,
          text: text,
          ask: ask,
          parsed: request.parsed,
          hints: request.hints ?? const [],
          candidates: request.candidates ?? const [],
          lang: request.lang,
        );
      },
    );
