program SysInfo_by_MarkFH;

uses
  Forms,
  Unit1 in 'Unit1.pas' {Form1};

// {$R *.res}

begin
  Application.Initialize;
  Application.Title := 'SysInfo by MarkFH';
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
