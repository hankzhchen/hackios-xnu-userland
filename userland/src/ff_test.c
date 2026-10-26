/*
 * ff_test: what os_feature_enabled answers in this system, for domain/feature pairs given on the command line
 * (24 October 2026: wifid never makes its auto-join manager because _os_feature_enabled_impl("CoreWiFi",
 * "UnifiedAutoJoin") answers no, though the stock /System/Library/FeatureFlags/Domain/CoreWiFi.plist says yes).
 * usage: ff_test DOMAIN FEATURE [DOMAIN FEATURE ...]
 */
#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>

extern bool _os_feature_enabled_impl(const char *domain, const char *feature);

int
main(int argc, char **argv)
{
	printf("ff_test: uid %d\n", getuid());
	for (int i = 1; i + 1 < argc; i += 2) {
		printf("ff_test: %s/%s: %s\n", argv[i], argv[i + 1], _os_feature_enabled_impl(argv[i], argv[i + 1]) ? "enabled" : "DISABLED");
	}
	return 0;
}
