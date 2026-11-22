import 'package:test/test.dart';
import 'package:xpense_agent/config/server_env.dart';

void main() {
  ServerEnv parse(Map<String, String> env) => ServerEnv.fromEnvironment(env);
  Matcher refused(String fragment) => throwsA(
    isA<ServerEnvError>().having(
      (e) => e.message,
      'message',
      contains(fragment),
    ),
  );

  const cloudRun = {
    'K_SERVICE': 'xpense-agent',
    'K_REVISION': 'xpense-agent-00001-abc',
    'GOOGLE_CLOUD_PROJECT': 'xpense-dev',
    'XPENSE_ROLE': 'agent',
    'PORT': '8080',
  };

  group('local', () {
    test('defaults: agent role, demo-xpense, port 8080, App Check on', () {
      final env = parse({});
      expect(env.role, XpenseRole.agent);
      expect(env.projectId, 'demo-xpense');
      expect(env.port, 8080);
      expect(env.onCloudRun, isFalse);
      expect(env.appCheckMode, AppCheckMode.enforce);
      expect(env.hasGeminiKey, isFalse);
      expect(env.otlpEndpoint, isNull);
    });

    test('jobs role', () {
      expect(parse({'XPENSE_ROLE': 'jobs'}).role, XpenseRole.jobs);
    });

    test('an unknown role is refused', () {
      expect(() => parse({'XPENSE_ROLE': 'both'}), refused('XPENSE_ROLE'));
    });

    test('a real project id is refused off Cloud Run', () {
      for (final project in ['xpense-dev', 'xpense-prod', 'other-project']) {
        expect(
          () => parse({'GOOGLE_CLOUD_PROJECT': project}),
          refused('demo-'),
          reason: project,
        );
        expect(
          () => parse({'GCLOUD_PROJECT': project}),
          refused('demo-'),
          reason: project,
        );
      }
    });

    test('another demo project is allowed', () {
      expect(parse({'GCLOUD_PROJECT': 'demo-other'}).projectId, 'demo-other');
    });

    test('App Check emulator mode needs the Auth emulator', () {
      expect(
        () => parse({'XPENSE_APP_CHECK': 'emulator'}),
        refused('FIREBASE_AUTH_EMULATOR_HOST'),
      );
      final env = parse({
        'XPENSE_APP_CHECK': 'emulator',
        'FIREBASE_AUTH_EMULATOR_HOST': '127.0.0.1:9399',
      });
      expect(env.appCheckMode, AppCheckMode.emulator);
    });

    test('an unknown App Check mode is refused', () {
      expect(() => parse({'XPENSE_APP_CHECK': 'off'}), refused('enforce'));
    });

    test('PORT must be a number', () {
      expect(() => parse({'PORT': 'http'}), refused('PORT'));
      expect(parse({'PORT': '9000'}).port, 9000);
    });

    test('the Gemini key and the OTLP endpoint are detected', () {
      final env = parse({
        'GEMINI_API_KEY': 'x',
        'OTEL_EXPORTER_OTLP_ENDPOINT': 'http://localhost:4318',
      });
      expect(env.hasGeminiKey, isTrue);
      expect(env.otlpEndpoint, 'http://localhost:4318');
    });

    test('blank values count as unset', () {
      final env = parse({'XPENSE_ROLE': ' ', 'GEMINI_API_KEY': ''});
      expect(env.role, XpenseRole.agent);
      expect(env.hasGeminiKey, isFalse);
    });
  });

  group('Cloud Run', () {
    test('reads the deployed settings', () {
      final env = parse(cloudRun);
      expect(env.onCloudRun, isTrue);
      expect(env.projectId, 'xpense-dev');
      expect(env.serviceName, 'xpense-agent');
      expect(env.serviceVersion, 'xpense-agent-00001-abc');
    });

    test('XPENSE_ROLE is required', () {
      expect(
        () => parse({...cloudRun}..remove('XPENSE_ROLE')),
        refused('XPENSE_ROLE'),
      );
    });

    test('the project must be explicit', () {
      expect(
        () => parse({...cloudRun}..remove('GOOGLE_CLOUD_PROJECT')),
        refused('GOOGLE_CLOUD_PROJECT'),
      );
    });

    test('App Check cannot be bypassed', () {
      expect(
        () => parse({
          ...cloudRun,
          'XPENSE_APP_CHECK': 'emulator',
          'FIREBASE_AUTH_EMULATOR_HOST': 'x:1',
        }),
        refused('Cloud Run'),
      );
    });
  });
}
