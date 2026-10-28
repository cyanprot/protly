// Bundle entry for the any-site path. Re-injection keeps the live instance.
globalThis.__protly ??= { run: async () => {}, toast: () => {} };
