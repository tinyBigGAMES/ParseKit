unit ParseLang.Common;

interface

uses
  System.SysUtils;

type

  { TParseLangPipelineCallbacks
    Pipeline built-in hooks populated by TParseLang so that script calls to
    setPlatform/setBuildMode/etc. forward into the build pipeline.
    A nil Proc means the built-in is silently ignored. }
  TParseLangPipelineCallbacks = record
    OnSetPlatform:   TProc<string>;
    OnSetBuildMode:  TProc<string>;
    OnSetOptimize:   TProc<string>;
    OnSetSubsystem:  TProc<string>;
    OnSetOutputPath: TProc<string>;
  end;

implementation

end.
