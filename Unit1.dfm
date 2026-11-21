object Form1: TForm1
  Left = 200
  Top = 100
  Width = 640
  Height = 520
  Caption = 'SysInfo by MarkFH v2.1'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 13
  object Memo1: TMemo
    Left = 8
    Top = 8
    Width = 616
    Height = 435
    Anchors = [akLeft, akTop, akRight, akBottom]
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Courier New'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssBoth
    TabOrder = 0
  end
  object Button1: TButton
    Left = 8
    Top = 452
    Width = 130
    Height = 28
    Anchors = [akLeft, akBottom]
    Caption = 'Refresh Data'
    TabOrder = 1
    OnClick = Button1Click
  end
  object Button2: TButton
    Left = 146
    Top = 452
    Width = 140
    Height = 28
    Anchors = [akLeft, akBottom]
    Caption = 'Save Report (.txt)'
    TabOrder = 2
    OnClick = Button2Click
  end
  object Button3: TButton
    Left = 294
    Top = 452
    Width = 140
    Height = 28
    Anchors = [akLeft, akBottom]
    Caption = 'Copy to Clipboard'
    TabOrder = 3
    OnClick = Button3Click
  end
end
