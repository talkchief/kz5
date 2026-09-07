# Callback media fixture timeout

The canonical current-source runner is
`scripts/test-acdc-gemini-canonical-callback.sh`. It compiles isolated production
and test BEAMs, checks production test-hook exclusions, runs the selected EUnit
suites, and verifies that source inputs remained unchanged. It does not deploy
the code or make telephone/provider calls.

On September 7, 2026, root reported a capped standalone run ending with 56
passed, zero assertion failures, and a cancelled test. Cancellation occurred
inside `meck_proc:start` while
`acdc_callback_caller_tests:returned_confirmation_media_is_language_safe_test/0`
was constructing a passthrough mock at source line 85. The run was **not a pass**:
the remaining suite and the cancelled case were not proven.

That test constructs passthrough mocks for the large `acdc_gemini_prompts` and
`kapps_call` modules. Mock construction is compilation/setup work within EUnit's
default five-second per-test budget, rather than production callback execution.
The test is now an explicit generator with a **30-second bound for that single
fixture**, including setup, the original assertions, and cleanup. No global
timeout, production timeout, assertion, language case, or suite selection was
weakened or removed. Nested cleanup also unloads the first mock if creation or
configuration of the second mock fails normally. A hard EUnit cancellation is
still a failed run; this does not claim cancellation-proof cleanup.

Root should rerun the full canonical runner under the existing resource and
network-isolation guard. The narrower standalone runner
`scripts/test-acdc-callback-caller.sh` also discovers the same bounded generator,
but its pass would not substitute for the full canonical run. Do not report
the timeout adjustment as callback performance evidence or deployment acceptance.

The editing agent performed source review only and did not run either suite.

Root subsequently ran the full network-isolated canonical suite at192MiB with
512MiB reserve and a900-second unit bound (`142a1a/654902`): **all87 tests
passed**, including this unchanged language-safety case. The final stable-input
SHA-256 is `9d8887b6e3e14d07dd7e251b56f0a228dee57192c93a14d82ca41c75385d36dd`.
No live module, database, telephone call or provider request was involved.
