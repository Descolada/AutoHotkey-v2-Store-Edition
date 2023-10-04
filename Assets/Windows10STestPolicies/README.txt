This package contains the following:

SiPolicy_Enforced.p7b - Enforces the same signing requirements as for Windows 10 S
SiPolicy_Audit.p7b - Has the same rules defined as Windows 10 S, but only logs events for things that would have been blocked, allowing all binaries to run
SiPolicy_DevMode_Enforced.p7b - Enforces the same signing requirements as for Windows 10 S, but also permits things signed with the AppXTest certificate included in this package to run
AppXTestRootAgency directory - contains a test certificate and private key to allow binaries to be signed that will be trusted by the DevMode policy, so that testing can happen during development without Store signing

The policies must be renamed to SIPolicy.p7b, installed in \Windows\System32\CodeIntegrity\SIPolicy.p7b, and the system rebooted.

Warning: the enforced policies will block untrusted things including drivers which can lead to boot failures. It is recommended to test the Audit mode policy first or to use a Virtual Machine.
