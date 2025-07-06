unit uFitPedidosCloud;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  Forms,
  Controls,
  Graphics,
  Dialogs,
  StdCtrls,
  StrUtils,
  ComCtrls, ExtCtrls,
  IdHTTP,
  Variants,
  IniFiles,
  DataSet.Serialize,
  RESTRequest4D,
  ZConnection,
  ZDataset,
  DB,
  fpjson,
  jsonparser,
  memds;

type

  { TForm1 }

  TForm1 = class(TForm)
    btnIntegrar: TButton;
    btnSair: TButton;
    btnFaturados: TButton;
    IdHTTP1: TIdHTTP;
    Image1: TImage;
    lblPasso1: TLabel;
    lblPasso2: TLabel;
    lblPasso3: TLabel;
    lblPOk1: TLabel;
    lblPOk2: TLabel;
    lblPOk3: TLabel;
    mtPedidos: TMemDataset;
    mtItensPedido: TMemDataset;
    pBar: TProgressBar;
    procedure btnFaturadosClick(Sender: TObject);
    procedure btnIntegrarClick(Sender: TObject);
    procedure btnSairClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    function getJsonArray(aJSON : String) : String;
  private
    vCon          : TZConnection;
    QryIns        : TZQuery;     // Inserir pedido
    QrySQL        : TZQuery;     // Consultas diversas
    QryInsIPed    : TZQuery;     // Inserir itens do pedido
    QryInsVend    : TZQuery;     // Inserir vendedores vendedor
    QryInsVendMob : TZQuery;     // Inserir vendedores mb_usuario
    URLBase       : String;
    REST_key      : String;
    Acrescenta    : String;
    Multiplica    : Integer;
    TraceOn       : String;

    vIni        : TIniFile;

    procedure Log(aLogMessage: string; RaiseException: Boolean);
    procedure CreateLogFile(FileName : String);

    procedure ChecaIniFile;
    procedure CarregaBanco;
    procedure Consultas;
    procedure IntegraPedidosCloud;
    procedure AtualizarPedidosFaturados;

    function  getInsertPedido : String;
    function  getInsertVendedor : String;
    function  getInsertVendedorMobile : String;
    function  getVendedorMobile : string;
    function  getProximoVendedor : string;

    function  getInsertItemPedido : String;
    function  VerificaVendedorMobile(vendedor_id : integer) : String ;

    function  getCliente : String;
    function  getPedidoMobile : String;
    function  getItensVenda : String;
    function  getVendedor : String;

    function  getProduto : String;
    function  Aspas(cValue: String) : String;

  public

  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }
procedure TForm1.btnIntegrarClick(Sender: TObject);
begin
    btnSair.SetFocus;
    btnIntegrar.Enabled:=False;
    IntegraPedidosCloud;
    ShowMessage('Integração realizada');
    Application.Terminate;
end;

procedure TForm1.btnFaturadosClick(Sender: TObject);
begin
  btnSair.SetFocus;
  btnFaturados.Enabled:=False;
  AtualizarPedidosFaturados;
  ShowMessage('Integração realizada');
  Application.Terminate;
end;

procedure TForm1.btnSairClick(Sender: TObject);
begin
  Application.Terminate;
end;

procedure TForm1.IntegraPedidosCloud;
var
  // Respostas de consultas REST
  vRespPed    : IResponse;
  vRespItens  : IResponse;
  vRespInteg  : IResponse;

  URLPed      : string;
  URLItem     : string;
  URLPut      : string;

  // Estruturas JSON
  vPedidos    : string;
  vItens      : string;

  jPedidos    : TJSONData;
  jItens      : TJSONData;

  // Campos do pedido
  pPedido     : string;
  pdtpedido   : string;
  pdataped    : string;
  pVendedor   : string;
  pCliente    : string;
  pNomCli     : string;
  pCnpjCli    : string;
  pFormPgto   : string;
  pTipo       : string;
  pObs        : string;
  pRota       : string;
  pTotal      : string;
  // Campos do item pedido
  iId         : string;
  iproduto    : string;
  iquantidade : string;
  iunitario   : string;
  itotal      : string;
  iunidade    : string;
  idescricao  : string;
  iOrdem      : integer;
  //
  vSQL        : string;
  vNroPed     : integer;

begin
  URLPed   := Trim(URLBase)+'pedidosabertos';
  URLItem  := Trim(URLBase)+'itenspedido/';

  lblPasso1.Font.Bold := True;
  lblPasso1.Visible   := True;
  Application.ProcessMessages;

  vRespPed := TRequest.New.BaseURL(trim(URLPed))
    .AddHeader('Authorization', 'Basic '+trim(REST_Key))
    .Accept('application/json')
    .Get;

  if (vRespPed.StatusCode = 200) and (trim(vRespPed.Content) <> '') then
  begin
    //ShowMessage(vRespPed.Content);
    vPedidos := getJsonArray(vRespPed.Content);
    //ShowMessage(vPedidos);
    jPedidos := GetJSON(vPedidos);
    //ShowMessage(jPedidos.AsJSON);

    mtPedidos.Clear(False);
    mtPedidos.Close;
    mtPedidos.Active := true;
    mtPedidos.LoadFromJSON(jPedidos.AsJSON);

    if TraceOn = 'S' Then
    begin
       Log('Total de Pedidos para sincronizar :' + IntToStr(mtPedidos.RecordCount), False);
       Log('Pedidos encontrados :', False);
       Log(jPedidos.AsJSON, False);
    end;

    Log('Pedidos para sincronizar', False);
    Log(jPedidos.AsJSON, False);

    pBar.Min:=0;
    pBar.Max:=mtPedidos.RecordCount;
    pBar.Step:=1;
    pBar.Position:=0;
    pBar.Visible:=True;

    mtPedidos.First;

    lblPOk1.Visible     := True;
    lblPasso2.Font.Bold := True;
    lblPasso2.Visible   := True;
    Application.ProcessMessages;

    vCon.StartTransaction;

    while not mtPedidos.EOF do
    begin
      pPedido    := mtPedidos.FieldByName('id').AsString;
      pdtpedido  := mtPedidos.FieldByName('dtpedido').AsString;
      pVendedor  := mtPedidos.FieldByName('vendedor').AsString;

      pVendedor := VerificaVendedorMobile(StrToInt(mtPedidos.FieldByName('vendedor').AsString));

      pCliente   := mtPedidos.FieldByName('cliente').AsString;
      pTipo      := mtPedidos.FieldByName('tipo').AsString;
      pFormPgto  := mtPedidos.FieldByName('forma_pagamento').AsString;
      pObs       := mtPedidos.FieldByName('obs').AsString;
      pTotal     := mtPedidos.FieldByName('total').AsString;

      pBar.Position:=pBar.Position + 1;

      if TraceOn = 'S' Then
         begin
            Log('Pedido :' + pPedido +
                ' Vendedor : ' + pVendedor +
                ' Cliente :' + pCliente +
                ' Valor :' + pTotal , False);
            Log(jPedidos.AsJSON, False);
         end;

      // Insere na base da retaguarda
      vSQL := getInsertPedido;
       // Quando Acrescenta for S vai montar o número do pedido assim:
      // codigo do vendedor inicia o número do pedido
      // 25000122  -> vendedor 25 pedido 122
      //
      if Acrescenta = 'S' Then
        vNroPed := ((StrToInt(pVendedor) * Multiplica) +  StrToInt(pPedido))
      else
        vNroPed := StrToInt(pPedido);

      vSQL := vSQL + '(' + IntToStr(vNroPed) +',';
      vSQL := vSQL + pCliente +',';
      vSQL := vSQL + pVendedor +',';
      vSQL := vSQL + pFormPgto +',';
      //
      // Busca dados do cliente
      QrySQL.Close;
      QrySQL.SQL.Clear;
      QrySQL.SQL.Text := getCliente ;
      QrySQL.ParamByName('COD_CLI').AsInteger   := StrToInt(pCliente);
      QrySQL.Open;
      try
          QrySQL.Open;
      except
      on e: Exception do
        begin
           raise Exception.Create('Erro ao buscar dados do cliente ' + Chr(13) + Chr(13) + E.Message);
        end;
      end;

      If QrySQL.IsEmpty then
      begin
        pCnpjCli := '11111111111111';
        pNomCli  := '**** CLIENTE NAO CADASTRADO ***';
        pRota    := '1';
      end
      else
      begin
        pCnpjCli := Trim(QrySQL.FieldByName('CNPJ_CLI').AsString);
        pNomCli  := Trim(QrySQL.FieldByName('NOME_FANTASIA').AsString);
        pRota    := Trim(QrySQL.FieldByName('ROTA').AsString);
      end;
      QrySQL.Close;

      vSQL := vSQL + Aspas(pCnpjCli) + ',';
      vSQL := vSQL + Aspas(Copy(pNomCli,1,35))+ ',';

      pdataped := copy(pdtpedido,9,2)+'.'+copy(pdtpedido,6,2)+'.'+copy(pdtpedido,1,4);

      vSQL := vSQL + Aspas(pdataped) + ',';
      vSQL := vSQL + pTotal + ',';
      vSQL := vSQL + '0' + ',';
      vSQL := vSQL + pTotal + ',';
      vSQL := vSQL + Aspas(' ') + ',';
      vSQL := vSQL + Aspas('P') + ',';
      vSQL := vSQL + Aspas(pdataped) + ',';
      if pTipo = '1' then
         vSQL := vSQL + Aspas('VENDA - '+Trim(pObs)) + ',';
      if pTipo = '2' then
         vSQL := vSQL + Aspas('TROCA - '+Trim(pObs)) + ',';
      if pTipo = '3' then
         vSQL := vSQL + Aspas('BONIFICACAO - '+Trim(pObs)) + ',';
      vSQL := vSQL + pRota + ', ';
      vSQL := vSQL + 'null, ';
      vSQL := vSQL + '0, ';
      vSQL := vSQL + 'null, ';
      vSQL := vSQL + 'null, ';
      vSQL := vSQL + 'null, ';
      vSQL := vSQL + 'null) ';

      // Monta e executa insert
      QryIns.Close;
      QryIns.SQL.Clear;
      QryIns.SQL.Text := vSQL ;

      try
         QryIns.ExecSQL;
      except
        on e: Exception do
        begin
          ShowMessage('Erro ao atualizar base de pedidos mobile ' + Chr(13) + Chr(13) + E.Message);
          Log('Erro ao atualizar base de pedidos mobile ' + Chr(13) + Chr(13) + E.Message, False);
        end;
      end;

      vRespItens := TRequest.New.BaseURL(trim(URLItem)+trim(pPedido))
          .AddHeader('Authorization', 'Basic '+trim(REST_Key))
              .Accept('application/json')
                  .Get;


      if (vRespItens.StatusCode = 200) and (trim(vRespItens.Content) <> '') then
      begin

          //ShowMessage(vResponse.Content);
          vItens := getJsonArray(vRespItens.Content);
          //ShowMessage(vItens);
          jItens := GetJSON(vItens);

          Log('Itens do pedido '+trim(pPedido)+' :', False);
          Log(jItens.AsJSON, False);

          mtItensPedido.Clear(False);
          mtItensPedido.Close;
          mtItensPedido.Active := true;
          mtItensPedido.LoadFromJSON(jItens.AsJSON);

          mtItensPedido.First;

          iOrdem := 0;

          while not mtItensPedido.EOF do
          begin

             iId         := mtItensPedido.FieldByName('id').AsString;
             iProduto    := mtItensPedido.FieldByName('produto').AsString;
             iQuantidade := mtItensPedido.FieldByName('quantidade').AsString;
             iUnitario   := mtItensPedido.FieldByName('unitario').AsString;
             iTotal      := mtItensPedido.FieldByName('total').AsString;
             iOrdem      := iOrdem + 1;

             vSQL := getInsertItemPedido;
             vSQL := vSQL + '( '+ iId + ', ';           // ID
             vSQL := vSQL + IntToStr(vNroPed) + ', ';   // ID_VENDA_CABECALHO
             vSQL := vSQL + Aspas(iProduto)+ ', ';      // ID_PRODUTO
             vSQL := vSQL + IntToStr(iOrdem) + ', ';               // ITEM

             // Busca dados do produto
             QrySQL.Close;
             QrySQL.SQL.Clear;
             QrySQL.SQL.Text := getProduto ;
             QrySQL.ParamByName('COD_PRO').AsInteger := StrToInt(iProduto);
             QrySQL.Open;
             try
               QrySQL.Open;
             except
             on e: Exception do
              begin
               vCon.Rollback;
               Log('Erro ao buscar dados do produto ' +
                   Chr(13) + Chr(13) + E.Message, True);
              end;
             end;

             If QrySQL.IsEmpty then
             begin
               idescricao := '**** PRODUTO NAO CADASTRADO ***';
               iunidade   := 'XX';
             end
             else
             begin
               idescricao := QrySQL.FieldByName('NOME_PRO').AsString;
               iunidade   := QrySQL.FieldByName('DESCRICAO').AsString;
             end;
             QrySQL.Close;

             vSQL := vSQL + Aspas(Copy(idescricao,1,35))+ ', ';  // DESC_PROD
             vSQL := vSQL + Aspas(Copy(iunidade,1,2))+ ', ';     // UN
             vSQL := vSQL + iUnitario+ ', ';                     // VALOR_UNITARIO
             vSQL := vSQL + iQuantidade+ ', ';                   // QUANTIDADE
             vSQL := vSQL + iTotal+ ', ';                        // TOTAL_ITEM
             vSQL := vSQL + '0'+ ', ';                           // DESCONTO
             vSQL := vSQL + iTotal+ ', ';                        // VALOR_TOTAL
             vSQL := vSQL + Aspas('A')+ ', ';                    // ST
             vSQL := vSQL + Aspas(' ')+ ', ';                    // SINCRONIZADO
             vSQL := vSQL + Aspas(pdataped)+ ', ';               // DATA_PED
             vSQL := vSQL + '0'+ ', ';                           // VL_DESCONTO
             vSQL := vSQL + 'NULL'+ ', ';                        // DEVOLVIDO
             vSQL := vSQL + 'NULL'+ ', ';                        // QUANTIDADE_DEV
             vSQL := vSQL + 'NULL'+ ', ';                        // EXCLUIDO
             vSQL := vSQL + iQuantidade+ ')';                    // QTD ORIGINAL

             // Insere itens do pedido na base da retaguarda
             QryInsIPed.Close;
             QryInsIPed.SQL.Clear;
             QryInsIPed.SQL.Text := vSQL;

             // ShowMessage(vSQL);

             try
                QryInsIPed.ExecSQL;
             except
               on e: Exception do
               begin
                 vCon.Rollback;
                 Log('Erro ao atualizar base de itens de pedidos cloud ' +
                     Chr(13) + Chr(13) + E.Message, True);
               end;
             end;

             mtItensPedido.Next;
          end;

      end;

      mtPedidos.Next;
    end;

    vCon.Commit;

    mtItensPedido.Close;

    pBar.Visible:=False;
    pBar.Step:=1;
    pBar.Position:=0;

    lblPOk2.Visible     := True;
    lblPasso3.Font.Bold := True;
    lblPasso3.Visible   := True;
    Application.ProcessMessages;
    // Marcar pedidos como integrados na base do cloud

    URLPut   := Trim(URLBase)+'pedidosituacao';

    mtPedidos.First;
    while not mtPedidos.EOF do
    begin
      pPedido    := mtPedidos.FieldByName('id').AsString;

      pBar.Position:=pBar.Position + 1;

      try
         if TraceOn = 'S' Then Log('Alterando a situação do pedido ' + Trim(pPedido) , False);
         if TraceOn = 'S' Then Log('url ' + trim(URLPut) , False);

         vRespInteg := TRequest.New.BaseURL(trim(URLPut))
             .AddHeader('Authorization', 'Basic '+trim(REST_Key))
             .AddBody('{ "pedido": "'+ pPedido + '", "situacao":"2"}')
             .Accept('application/json')
             .Put;
      except
        on e: Exception do
         begin
           Log('Erro ao atualizar situação do pedido '+pPedido+' no cloud ...' +
               Chr(13) + Chr(13) + E.Message, True);
         end;
      end;

      if (vRespInteg.StatusCode <> 200) then
      begin
        Log('Erro ao atualizar situação do pedido '+pPedido+' no cloud ...', True);
      end;

      mtPedidos.Next;
    end;

    lblPOk3.Visible     := True;
    Application.ProcessMessages;

    mtPedidos.Close;

    if TraceOn = 'S' Then Log('Pedidos do Cloud sincronizados!', False);

    ShowMessage('Pedidos do Cloud sincronizados!');

    lblPasso1.Visible:=False;
    lblPasso2.Visible:=False;
    lblPasso3.Visible:=False;

    lblPOk1.Visible:=False;
    lblPOk2.Visible:=False;
    lblPOk3.Visible:=False;

    pBar.Visible:=False;
    pBar.Min:=0;
    pBar.Max:=0;
    pBar.Step:=1;
    pBar.Position:=0;

  end;

end;

procedure TForm1.AtualizarPedidosFaturados;
var
  // Respostas de consultas REST
  vRespPed    : IResponse;
  vRespInteg  : IResponse;

  URLPed      : string;
  URLPut      : string;
  URLSit      : string;

  // Estruturas JSON
  vPedidos    : string;
  jPedidos    : TJSONData;
  lbody       : string;

  // Campos do pedido
  pPedido     : string;
  pVendedor   : string;
  // Campos do item pedido
  iproduto    : string;
  iquantidade : string;
  pVenda      : integer;
  //
  vNroPed     : integer;

begin
  URLPed   := Trim(URLBase)+'pedidos/2';
  URLPut   := Trim(URLBase)+'itemupdateqtd';
  URLSit   := Trim(URLBase)+'pedidosituacao';

  lblPasso1.Font.Bold := True;
  lblPasso1.Visible   := True;
  Application.ProcessMessages;

  vRespPed := TRequest.New.BaseURL(trim(URLPed))
    .AddHeader('Authorization', 'Basic '+trim(REST_Key))
    .Accept('application/json')
    .Get;

  if (vRespPed.StatusCode = 200) and (trim(vRespPed.Content) <> '') then
  begin
    //ShowMessage(vRespPed.Content);
    vPedidos := getJsonArray(vRespPed.Content);
    //ShowMessage(vPedidos);
    jPedidos := GetJSON(vPedidos);
    //ShowMessage(jPedidos.AsJSON);

    mtPedidos.Clear(False);
    mtPedidos.Close;
    mtPedidos.Active := true;
    mtPedidos.LoadFromJSON(jPedidos.AsJSON);

    if TraceOn = 'S' Then
    begin
       Log('Total de Pedidos para sincronizar :' + IntToStr(mtPedidos.RecordCount), False);
       Log('Pedidos encontrados :', False);
       Log(jPedidos.AsJSON, False);
    end;

    Log('Pedidos para sincronizar', False);
    Log(jPedidos.AsJSON, False);

    pBar.Min:=0;
    pBar.Max:=mtPedidos.RecordCount;
    pBar.Step:=1;
    pBar.Position:=0;
    pBar.Visible:=True;

    mtPedidos.First;

    lblPOk1.Visible     := True;
    lblPasso2.Font.Bold := True;
    lblPasso2.Visible   := True;
    Application.ProcessMessages;

    while not mtPedidos.EOF do
    begin
        pPedido    := mtPedidos.FieldByName('id').AsString;
        pVendedor  := mtPedidos.FieldByName('vendedor').AsString;

        pBar.Position := pBar.Position + 1;
        Application.ProcessMessages;

        // Quando Acrescenta for S vai montar o número do pedido assim:
        // codigo do vendedor inicia o número do pedido
        // 25000122  -> vendedor 25 pedido 122
        //
        if Acrescenta = 'S' Then
          vNroPed := ((StrToInt(pVendedor) * Multiplica) +  StrToInt(pPedido))
        else
          vNroPed := StrToInt(pPedido);

        if TraceOn = 'S' Then Log('Processando o pedido web    ' + pPedido , False);
        if TraceOn = 'S' Then Log('Processando o pedido mobile ' + intToStr(vNroPed) , False);

        //
        // Consulta o pedido mobile no backoffice para encontrar a venda
        QrySQL.Close;
        QrySQL.SQL.Clear;
        QrySQL.SQL.Text := getPedidoMobile ;
        QrySQL.ParamByName('ID').AsInteger := vNroPed;
        try
            QrySQL.Open;
        except
        on e: Exception do
          begin
             raise Exception.Create('Erro ao buscar dados do pedido ' +  intToStr(vNroPed) + Chr(13) + Chr(13) + E.Message);
          end;
        end;

        If QrySQL.IsEmpty then
        begin
          QrySQL.Close;
          Log('Erro ao buscar o pedido de venda nro ' + intToStr(vNroPed) + ' !', false);
        end
        else
        begin
          pVenda := QrySQL.FieldByName('codven').AsInteger;

          QrySQL.Close;

          if pVenda <> 0 then
          begin
            // ITENS_VENDA
            QrySQL.SQL.Clear;
            QrySQL.SQL.Text := getItensVenda ;
            QrySQL.ParamByName('COD_VEN').AsInteger := pVenda;
            try
                QrySQL.Open;
            except
            on e: Exception do
              begin
                 raise Exception.Create('Erro ao buscar dados da venda ' +  intToStr(pVenda) + Chr(13) + Chr(13) + E.Message);
              end;
            end;

            If QrySQL.IsEmpty then
            begin
                 QrySQL.Close;
                 Log('Erro ao buscar itens da venda número ' +  intToStr(pVenda) + ' !', false);
            end
            else
            begin
                 // Atualiza quantidades no pedido na web
                 lbody := '{ "data": [';
                 QrySQL.First;
                 while not QrySQL.EOF do
                 begin
                      iproduto    := QrySQL.FieldByName('COD_PRO').AsString;
                      iquantidade := ReplaceStr(ReplaceStr(QrySQL.FieldByName('QUANT').AsString, '.',''),',','.');

                      lbody := lbody + '{"produto":"' + iproduto + '", "quant": "' + iquantidade + '" }';

                      QrySQL.Next;
                      if not QrySQL.EOF then
                         lbody := lbody + ',';
                 end;

                 lbody := lbody + ' ] } ';

                 try
                     if TraceOn = 'S' Then
                        Log('Alterando a quantidade do pedido ' + Trim(pPedido) , False);
                        Log('Conteudo : ' + lbody , False);

                     vRespInteg := TRequest.New.BaseURL(trim(URLPut)+'/'+pPedido)
                      .AddHeader('Authorization', 'Basic '+trim(REST_Key))
                      .AddBody(lbody)
                      .Accept('application/json')
                      .Put;
                  except
                      on e: Exception do
                            begin
                                 Log('Erro ao atualizar da quantidade do item! Pedido: '+ pPedido+' Produto: ' + iproduto +
                                           Chr(13) + Chr(13) + E.Message, False);
                            end;
                  end;

                  if (vRespInteg.StatusCode <> 200) then
                  begin
                      Log('Erro ao atualizar da quantidade do item! Pedido: '+ pPedido+' Produto: ' + iproduto +' (Cloud) ...', False);
                  end;

                  // Marcar pedido como faturado na base do cloud
                  try
                     if TraceOn = 'S' Then Log('Alterando a situação do pedido ' + Trim(pPedido) , False);
                     if TraceOn = 'S' Then Log('url ' + trim(URLSit) , False);

                     vRespInteg := TRequest.New.BaseURL(trim(URLSit))
                         .AddHeader('Authorization', 'Basic '+trim(REST_Key))
                         .AddBody('{"pedido":"' + pPedido + '", "situacao":"3"}')
                         .Accept('application/json')
                         .Put;
                  except
                    on e: Exception do
                     begin
                       Log('Erro ao atualizar situação do pedido '+pPedido+' no cloud ...' +
                           Chr(13) + Chr(13) + E.Message, True);
                     end;
                  end;

                  if (vRespInteg.StatusCode <> 200) then
                  begin
                    Log('Erro ao atualizar situação do pedido '+pPedido+' no cloud ...', True);
                  end;

            end;
            QrySQL.Close;

          end;

        end;

        mtPedidos.Next;
    end;

    mtPedidos.Close;

    if TraceOn = 'S' Then Log('Quantidade dos Pedidos sincronizadas!', False);

    ShowMessage('Quantidades dos Pedidos Sincronizados!');

    lblPasso1.Visible:=False;
    lblPasso2.Visible:=False;
    lblPasso3.Visible:=False;

    lblPOk1.Visible:=False;
    lblPOk2.Visible:=False;
    lblPOk3.Visible:=False;

    pBar.Visible:=False;
    pBar.Min:=0;
    pBar.Max:=0;
    pBar.Step:=1;
    pBar.Position:=0;
  end;
end;

{
 ROTINAS AULIXIARES
}
procedure TForm1.FormCreate(Sender: TObject);
begin

  try
    ChecaIniFile;
    CarregaBanco;
    Consultas;
  except
    on e: Exception do
    begin
      ShowMessage(e.Message);
      Application.Terminate;
    end;
  end;

end;

procedure TForm1.ChecaIniFile;
begin
  if not FileExists(ExtractFilePath(Application.ExeName) + 'ForcaVendas.ini') then
  begin
    raise Exception.Create('O arquivo ' + ExtractFilePath(Application.ExeName) + 'ForcaVendas.ini' + ' de parâmetro não existe!');
  end;
  vIni := TIniFile.Create(ExtractFilePath(Application.ExeName) + 'ForcaVendas.ini');
end;

procedure TForm1.CarregaBanco;
var
  vServer : String;
  vBanco  : String;
  vPorta  : integer;

begin
  vServer := vIni.ReadString('BASE', 'Servidor', '');
  vBanco  := vIni.ReadString('BASE', 'Banco', '');
  vPorta  := vIni.ReadInteger('BASE', 'Porta', 3050);
  vCon    := TZConnection.Create(nil);

  try
    vCon.Database        := vBanco;
    vCon.HostName        := vServer;
    vCon.Port            := vPorta;
    vCon.Protocol        := 'firebird';
    vCon.User            := 'SYSDBA';
    vCon.Password        := 'masterkey';
    vCon.LibraryLocation := 'fbclient.dll';

//    vCon.Params.Add('DriverID=FB');
//    vCon.Params.Add('CharSet=WIN1252');


  except
      on e: Exception do
      begin
        raise Exception.Create('Erro ao carregar configuração, verifique a configuração' + Chr(13) + Chr(13) + E.Message);
      end;
  end;

  URLBase    := vIni.ReadString('CLOUD', 'URLBase', 'Error');
  REST_key   := vIni.ReadString('CLOUD', 'REST_key', 'Error');
  Acrescenta := vIni.ReadString('GERAL', 'AcrescentaVendedor', 'S');
  Multiplica := vIni.ReadInteger('GERAL', 'Multiplica', 1000000);

  If Trim(URLBase) = 'Error' then
  begin
    raise Exception.Create('Erro ao carregar configuração da URL base, verifique a configuração');
  end;

  TraceOn:= vIni.ReadString('GERAL', 'TraceAtivo', 'N');;

end;

function TForm1.Aspas(cValue: String) : String;
begin
  result := Chr(39) + trim(cValue) + Chr(39);

end;
function TForm1.getJsonArray(aJSON: String): String;
var
  lKey : string;
  lini : integer;
  lfim : integer;
  lres : string;

begin
   lres := '';
   lkey := 'data":';
   lini := pos(lKey,aJSON);
   lini := lini + 6 ;
   lfim := length(aJSON);
   lfim := lfim - lini;
   lres := copy(aJSON, lini, lfim);

   result := lres;

end;

procedure TForm1.Log(aLogMessage: string; RaiseException: Boolean);
var
  Flog        : TextFile;
  FN          : String;
  DateTimeNow : TDateTime;
  SulfixName  : String;
begin
  DateTimeNow := Now();

  SulfixName  := FormatDateTime('yyyyMMdd', DateTimeNow);

  FN := 'FitIntegradorPedidosCloud-'+Trim(SulfixName)+'.log';

  if (not FileExists(FN)) then
  begin
    CreateLogFile(FN);
  end;

  AssignFile(FLog, FN);
  Append(FLog);

  WriteLn(FLog, DateTimeToStr(Now) + ' - FitIntegradorPedidosCloud : ' + aLogMessage);

  CloseFile(FLog);

  if RaiseException then
    raise Exception.Create('FitIntegradorPedidosCloud - '+aLogMessage);

End;

procedure TForm1.CreateLogFile(FileName : String);
var
  FLog : TextFile;
begin

  AssignFile(FLog, FileName);
  Rewrite(FLog);
  Append(FLog);

  WriteLn(FLog, '');
  WriteLn(FLog, 'Arquivo criado em ' + DateTimeToStr(Now));
  WriteLn(FLog, '');

  CloseFile(FLog);
end;

function TForm1.VerificaVendedorMobile(vendedor_id : integer) : String;
var
  // Respostas de consultas REST
  vRespVend : IResponse;
  URLVend   : string;
  // Estruturas JSON
  JSONData: TJSONData;
  JSONObject: TJSONObject;
  JSONArray: TJSONArray;
  //
  vId       : String;
  vDesc     : String;
  vLogin    : String;
  pVendedor : String;
  temVend   : integer;
  //
  vSQL   : string;
begin
    //
    // Consulta vendedor na tabela Vendedor pelo código no mobile/web
    QrySQL.Close;
    QrySQL.SQL.Clear;
    QrySQL.SQL.Text := getVendedor;
    QrySQL.ParamByName('cod_mob').AsInteger := vendedor_id;
    QrySQL.Open;
    try
        QrySQL.Open;
    except
    on e: Exception do
      begin
         raise Exception.Create('Erro ao buscar dados do vendedor ' + Chr(13) + Chr(13) + E.Message);
      end;
    end;

    If QrySQL.IsEmpty then
    begin
      pVendedor := '0';
      temVend   := 1;
    end
    else
    begin
      temVend   := 0;
      pVendedor := Trim(QrySQL.FieldByName('cod_vend').AsString);
    end;

    QrySQL.Close;

    // Verifica existencia do vendedor na tabela mb_usuario pelo código no mobile/web
    QrySQL.Close;
    QrySQL.SQL.Clear;
    QrySQL.SQL.Text := getVendedorMobile;
    QrySQL.ParamByName('cod_mob').AsInteger := vendedor_id;

    try
        QrySQL.Open;
    except
    on e: Exception do
      begin
         raise Exception.Create('Erro ao buscar dados do cliente ' + Chr(13) + Chr(13) + E.Message);
      end;
    end;

    If QrySQL.IsEmpty then
    begin
       if (temVend = 1) then
           temVend := 3
       else
           temVend := 2;
    end;
    QrySQL.Close;

    // Vendedor não encontrado na base local, busca dados na web
    if (temVend > 0 ) then
    begin
        URLVend  := Trim(URLBase)+'obtervendedor/';

        vRespVend := TRequest.New.BaseURL(trim(URLVend)+trim(intTostr(vendedor_id)))
                  .AddHeader('Authorization', 'Basic '+trim(REST_Key))
                  .Accept('application/json')
                  .Get;

        if (vRespVend.StatusCode = 200) and (trim(vRespVend.Content) <> '') then
        begin
            // Parseando o JSON
            JSONData := GetJSON(vRespVend.Content);
            JSONObject := JSONData as TJSONObject;
            // Acessando array "data"
            JSONArray := JSONObject.Arrays['data'];
            // Pegando o primeiro objeto do array
            JSONObject := JSONArray.Objects[0];
            // Acessando propriedades do objeto dentro do array
            vId    := JSONObject.Strings['id'];
            vDesc  := JSONObject.Strings['nome'];
            vLogin := JSONObject.Strings['login'];
        end;
    end;

    // Vendedor não encontrado na base local, inclui vendedor
    if ((temVend = 1) or (temVend = 3)) then
    begin
         QrySQL.Close;
         QrySQL.SQL.Clear;
         QrySQL.SQL.Text := getProximoVendedor;
         try
             QrySQL.Open;
         except
         on e: Exception do
           begin
              raise Exception.Create('Erro ao buscar dados do cliente ' + Chr(13) + Chr(13) + E.Message);
           end;
        end;

        pVendedor  := QrySQL.FieldByName('NEXTVAL').AsString;

        vSQL := getInsertVendedor;
        vSQL := vSQL + '( ' + pVendedor + ', ';             // cod_vend
        vSQL := vSQL + Aspas(vDesc)+ ', ';                  // nome_vend
        vSQL := vSQL + Aspas('S')+ ', ';                    // ativo_vend
        vSQL := vSQL +  '0, ';                              // comissao_vend
        vSQL := vSQL + Aspas('123')+ ', ';                  // senha_venda
        vSQL := vSQL + vId+ ')';                            // cod_mob

        // Insere vendedor na tabela de vendedores
        QryInsVend.Close;
        QryInsVend.SQL.Clear;
        QryInsVend.SQL.Text := vSQL;

        try
           QryInsVend.ExecSQL;
        except
          on e: Exception do
          begin
            vCon.Rollback;
            Log('Erro ao cadastrar vendedor vindo do cloud ' +
                Chr(13) + Chr(13) + E.Message, True);
          end;
        end;

        QryInsVend.Close;
        // Liberando memória
    end;

    // vendedor não encontrado na tabela mb_usuario, inserir registro
    if ((temVend = 2) or (temVend = 3)) then
    begin
        vSQL := getInsertVendedorMobile;
        vSQL := vSQL + '( ' + vId + ', ';                  // id
        vSQL := vSQL + Aspas(vDesc)+ ', ';                 // descricao
                     vSQL := vSQL + Aspas(vLogin)+ ', ';   // login
                     vSQL := vSQL + Aspas('123')+ ', ';    // senha
                     vSQL := vSQL + '1'+ ', ';             // regiao
                     vSQL := vSQL + vId+ ')';              // concentador

        // Insere itens do pedido na base da retaguarda
        QryInsVendMob.Close;
        QryInsVendMob.SQL.Clear;
        QryInsVendMob.SQL.Text := vSQL;

        try
           QryInsVendMob.ExecSQL;
        except
           on e: Exception do
           begin
             vCon.Rollback;
             Log('Erro ao cadastrar vendedor mobile vindo do cloud ' +
                Chr(13) + Chr(13) + E.Message, True);
           end;
        end;

        QryInsVendMob.Close;
        // Liberando memória
        JSONData.Free;
    end;

    result := intToStr(vendedor_id);
end;



function TForm1.getCliente : String;
begin
   RESULT := 'select '+
             ' cnpj_cli, coalesce(nome_fantasia,nome_cli) as nome_fantasia,  '  +
             ' 1 as rota '+
             'from cliente where cod_cli = :cod_cli';
end;

function TForm1.getVendedor : String;
begin
   result := 'select cod_vend from vendedor where cod_mob = :cod_mob';
end;

function TForm1.getVendedorMobile : String;
begin
   result := 'select id from mb_usuario where id = :cod_mob';
end;

function TForm1.getInsertPedido : String;
begin
   result := 'insert into mb_venda_cabecalhos '+
             ' (id, id_cliente, id_usuario,  ' +
             ' id_form_pg, cnpj_cpf_cli, client, data_venda, valor_venda,' +
             ' desconto, valor_final, sincronizado, status_venda, data_ped,' +
             ' obs, rota, entregue, qtde_dias, nosso_numero, data_entregue,' +
             ' romaneio, venda) values ';
end;

function TForm1.getInsertItemPedido : String;
begin
  RESULT := 'insert into mb_venda_detalhes  '+
            ' (id, id_venda_cabecalho, id_produto, item, desc_prod,'+
            ' un, valor_unitario, quantidade, total_item, desconto,'+
            ' valor_total, st, sincronizado, data_ped, vl_desconto,'+
            ' devolvido, quantidade_dev, excluido, qtd_orig) '+
            'values  ';
end;

function TForm1.getInsertVendedor : String;
begin
     result := 'insert into vendedor (cod_vend, nome_vend, ativo_vend, ' +
               'comissao_vend, senha_venda, cod_mob) values ';
end;

function TForm1.getInsertVendedorMobile : String;
begin
   result := 'insert into mb_usuario  '+
             '  (id, desc_usuario, login, senha, ' +
             ' id_regiao, concentrador) values ';
end;

function TForm1.getProduto : String;
BEGIN
   RESULT := 'select '+
             ' p.nome_pro, m.descricao ' +
             'from '+
             ' produto p, unidade_medida m '+
             'where '+
             '     p.cod_pro = :cod_pro '+
             ' and m.codigo = p.codigo_unidade_saida';
end;

function TForm1.getProximoVendedor : string;
begin
  result := 'select (max(cod_vend) + 1) as nextval from vendedor';
end;

function TForm1.getPedidoMobile : String;
begin
  result :=' select coalesce(venda, 0) as codven from MB_VENDA_CABECALHOS where id = :id ';
end;

function TForm1.getItensVenda : String;
begin
  result :=' select cod_pro, quant from ITENS_VENDA where cod_ven = :cod_ven order by ordem';
end;

procedure TForm1.Consultas;
begin
    try
       vCon.Connected       := True;
     except
         on e: Exception do
         begin
           raise Exception.Create('Erro ao conectar ao banco de dados, verifique a configuração' + Chr(13) + Chr(13) + E.Message);
         end;
     end;

    // Cria objetos para consultas
    QryIns := TZQuery.Create(nil);
    QryIns.Connection := vCon;

    QryInsIPed := TZQuery.Create(nil);
    QryInsIPed.Connection := vCon;

    QryInsVend := TZQuery.Create(nil);
    QryInsVend.Connection := vCon;

    QryInsVendMob := TZQuery.Create(nil);
    QryInsVendMob.Connection := vCon;

    QrySQL := TZQuery.Create(nil);
    QrySQL.Connection := vCon;

end;


end.

