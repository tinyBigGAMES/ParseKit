# Push Notes

## Parse.pas — Fix build settings sync after code generation

- Replaced the previous approach of reading settings back from `FBuild` after parsing with the correct approach of pushing the final values from `TParse` instance fields into `FBuild` after code generation
- Codegen emit handlers (e.g. `setTarget`, `setOptimizeLevel`, `setSubsystem`, `setBuildMode`) may update `FTargetPlatform`, `FOptimizeLevel`, `FSubsystem`, and `FBuildMode` on the `TParse` instance after `FBuild` was first configured
- Now calls `FBuild.SetTarget()`, `FBuild.SetOptimizeLevel()`, `FBuild.SetSubsystem()`, and `FBuild.SetBuildMode()` with the final field values so the Zig toolchain uses what the source file requested
