# Build 37: inline field errors without duplicates

On editable broker agreement steps, missing/invalid details appear once beside
their own fields. The repeated footer summary and its Fix buttons are removed
from those steps. Owner/tenant identity, optional email, amounts, shares,
dates and brokerage validation remain active. Property name/address/flat text
remain entirely optional, including blank text and arbitrary names like `rjh`.

The read-only review step retains correction navigation because it contains
no editable inputs. Following a correction opens the right person/step and
then shows only its inline errors. A resumed periods step with missing dates
opens the dates step rather than silently hiding its validation failure.
Operational save/network errors remain separate, truthful messages.

Fifteen targeted checks pass, including 320/363.4/440-pixel rendering, keyboard
insets, one occurrence per field error, clearing corrected fields, tenant 2
isolation, review-to-money corrections and restored date-step correction.
All 319 Flutter tests pass and analysis is clean. The signed AAB and isolated
APK are archived in Downloads; their source snapshot is unchanged during the
release pipeline and the Play upload signature is verified. Firebase Hosting
matches the release's web bytes.

The installed UI Test APK matches its archived hash. Fresh phone XML shows
one name error, one mobile error and no repeated summary; the corrected
synthetic owner advances to the working document step. The original app stays
on build 33 with its unchanged 11 October update timestamp.

Release artifact: `C:\Users\ajayb\Downloads\TrustKeyper-v2.0.0-build37-testing.aab`.
SHA-256: `0F31B3976189AA763F473F1D781D6765DF2046F36C5417136F8084498C06C59F`.
Evidence: `output/ui-audit/build37-artifacts.json`,
`output/ui-audit/build37-phone-verification.json` and the corresponding XML/PNG.

The normal app requires the build-37 signed AAB through Play internal testing.
Only the separate offline UI Test package may be installed directly here; the
original app/session remain untouched. This change is not whole-product
production acceptance or pixel-perfect certification.
