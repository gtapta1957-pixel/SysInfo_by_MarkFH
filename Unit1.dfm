object Form1: TForm1
  Left = 200
  Top = 100
  Width = 690
  Height = 530
  Caption = 'SysInfo by MarkFH v2.6'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clBlack
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 13
  object PanelTop: TPanel
    Left = 0
    Top = 0
    Width = 682
    Height = 46
    Align = alTop
    BevelOuter = bvNone
    Color = 8388608
    ParentFont = False
    TabOrder = 0
    object LblTitle: TLabel
      Left = 14
      Top = 7
      Width = 172
      Height = 16
      Caption = 'SysInfo by MarkFH v2.6'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWhite
      Font.Height = -13
      Font.Name = 'MS Sans Serif'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object LblSubtitle: TLabel
      Left = 14
      Top = 25
      Width = 247
      Height = 13
      Caption = 'User-Mode Hardware Diagnostics (Win95 - Win11)'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = 15780518
      Font.Height = -11
      Font.Name = 'MS Sans Serif'
      Font.Style = []
      ParentFont = False
    end
  end
  object PanelAccent: TPanel
    Left = 0
    Top = 46
    Width = 682
    Height = 3
    Align = alTop
    BevelOuter = bvNone
    Color = 16744448
    TabOrder = 1
  end
  object PageControl1: TPageControl
    Left = 8
    Top = 55
    Width = 666
    Height = 384
    ActivePage = TabOverview
    Anchors = [akLeft, akTop, akRight, akBottom]
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clBlack
    Font.Height = -11
    Font.Name = 'MS Sans Serif'
    Font.Style = []
    ParentFont = False
    TabOrder = 2
    object TabOverview: TTabSheet
      Caption = 'Overview'
      object lvOverview: TListView
        Left = 4
        Top = 4
        Width = 650
        Height = 348
        Align = alClient
        Columns = <
          item
            Caption = 'Component'
            Width = 175
          end
          item
            Caption = 'Details'
            Width = 455
          end>
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clBlack
        Font.Height = -11
        Font.Name = 'MS Sans Serif'
        Font.Style = []
        GridLines = True
        ParentFont = False
        ReadOnly = True
        RowSelect = True
        TabOrder = 0
        ViewStyle = vsReport
        OnCustomDrawItem = StandardListCustomDrawItem
        OnCustomDrawSubItem = StandardListCustomDrawSubItem
      end
    end
    object TabWindows: TTabSheet
      Caption = 'Windows'
      ImageIndex = 1
      object lvWindows: TListView
        Left = 4
        Top = 4
        Width = 650
        Height = 348
        Align = alClient
        Columns = <
          item
            Caption = 'Property'
            Width = 185
          end
          item
            Caption = 'Value'
            Width = 445
          end>
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clBlack
        Font.Height = -11
        Font.Name = 'MS Sans Serif'
        Font.Style = []
        GridLines = True
        ParentFont = False
        ReadOnly = True
        RowSelect = True
        TabOrder = 0
        ViewStyle = vsReport
        OnCustomDrawItem = StandardListCustomDrawItem
        OnCustomDrawSubItem = StandardListCustomDrawSubItem
      end
    end
    object TabProcessor: TTabSheet
      Caption = 'Processor'
      ImageIndex = 2
      object lvProcessor: TListView
        Left = 4
        Top = 4
        Width = 650
        Height = 348
        Align = alClient
        Columns = <
          item
            Caption = 'Property'
            Width = 185
          end
          item
            Caption = 'Value'
            Width = 445
          end>
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clBlack
        Font.Height = -11
        Font.Name = 'MS Sans Serif'
        Font.Style = []
        GridLines = True
        ParentFont = False
        ReadOnly = True
        RowSelect = True
        TabOrder = 0
        ViewStyle = vsReport
        OnCustomDrawItem = StandardListCustomDrawItem
        OnCustomDrawSubItem = StandardListCustomDrawSubItem
      end
    end
    object TabMemory: TTabSheet
      Caption = 'Memory'
      ImageIndex = 3
      object lvMemory: TListView
        Left = 4
        Top = 4
        Width = 650
        Height = 348
        Align = alClient
        Columns = <
          item
            Caption = 'Property'
            Width = 185
          end
          item
            Caption = 'Value'
            Width = 445
          end>
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clBlack
        Font.Height = -11
        Font.Name = 'MS Sans Serif'
        Font.Style = []
        GridLines = True
        ParentFont = False
        ReadOnly = True
        RowSelect = True
        TabOrder = 0
        ViewStyle = vsReport
        OnCustomDrawItem = StandardListCustomDrawItem
        OnCustomDrawSubItem = StandardListCustomDrawSubItem
      end
    end
    object TabVideo: TTabSheet
      Caption = 'Video'
      ImageIndex = 4
      object lvVideo: TListView
        Left = 4
        Top = 4
        Width = 650
        Height = 348
        Align = alClient
        Columns = <
          item
            Caption = 'Property'
            Width = 185
          end
          item
            Caption = 'Value'
            Width = 445
          end>
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clBlack
        Font.Height = -11
        Font.Name = 'MS Sans Serif'
        Font.Style = []
        GridLines = True
        ParentFont = False
        ReadOnly = True
        RowSelect = True
        TabOrder = 0
        ViewStyle = vsReport
        OnCustomDrawItem = StandardListCustomDrawItem
        OnCustomDrawSubItem = StandardListCustomDrawSubItem
      end
    end
    object TabDisks: TTabSheet
      Caption = 'Disks'
      ImageIndex = 5
      object lvDisks: TListView
        Left = 4
        Top = 4
        Width = 650
        Height = 348
        Align = alClient
        Columns = <
          item
            Caption = 'Drive'
            Width = 55
          end
          item
            Caption = 'Type'
            Width = 105
          end
          item
            Caption = 'Label'
            Width = 120
          end
          item
            Caption = 'File System'
            Width = 75
          end
          item
            Caption = 'Capacity / Free'
            Width = 175
          end
          item
            Caption = 'Usage'
            Width = 100
          end>
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clBlack
        Font.Height = -11
        Font.Name = 'MS Sans Serif'
        Font.Style = []
        GridLines = True
        ParentFont = False
        ReadOnly = True
        RowSelect = True
        TabOrder = 0
        ViewStyle = vsReport
        OnAdvancedCustomDrawItem = lvDisksAdvancedCustomDrawItem
        OnAdvancedCustomDrawSubItem = lvDisksAdvancedCustomDrawSubItem
      end
    end
  end
  object Button1: TButton
    Left = 8
    Top = 446
    Width = 125
    Height = 28
    Anchors = [akLeft, akBottom]
    Caption = 'Refresh Data'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clBlack
    Font.Height = -11
    Font.Name = 'MS Sans Serif'
    Font.Style = []
    ParentFont = False
    TabOrder = 3
    OnClick = Button1Click
  end
  object Button2: TButton
    Left = 141
    Top = 446
    Width = 135
    Height = 28
    Anchors = [akLeft, akBottom]
    Caption = 'Save Report (.txt)'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clBlack
    Font.Height = -11
    Font.Name = 'MS Sans Serif'
    Font.Style = []
    ParentFont = False
    TabOrder = 4
    OnClick = Button2Click
  end
  object Button3: TButton
    Left = 284
    Top = 446
    Width = 135
    Height = 28
    Anchors = [akLeft, akBottom]
    Caption = 'Copy to Clipboard'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clBlack
    Font.Height = -11
    Font.Name = 'MS Sans Serif'
    Font.Style = []
    ParentFont = False
    TabOrder = 5
    OnClick = Button3Click
  end
  object StatusBar1: TStatusBar
    Left = 0
    Top = 480
    Width = 682
    Height = 19
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clBlack
    Font.Height = -11
    Font.Name = 'MS Sans Serif'
    Font.Style = []
    Panels = <
      item
        Text = 'Ready'
        Width = 682
      end>
    ParentFont = False
  end
end
