unit ujmclient;

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
  Variants,
  IniFiles,
  DataSet.Serialize,
  RESTRequest4D,
  ZConnection,
  ZDataset,
  DB,
  fpjson,
  memds;

type

  { TForm1 }

  TForm1 = class(TForm)
    btnIntegrar: TButton;
    btnSair: TButton;
    lblPasso1: TLabel;
    lblPasso2: TLabel;
    lblPasso3: TLabel;
    lblPasso4: TLabel;
    lblP1Ok: TLabel;
    lblP2Ok: TLabel;
    lblP3Ok: TLabel;
    lblP4Ok: TLabel;
    mtPedidos: TMemDataset;
    mtItensPedido: TMemDataset;
    procedure btnIntegrarClick(Sender: TObject);
    procedure btnSairClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    function getJsonArray(aJSON : String) : String;
  private
    vCon       : TZConnection;
    QryIns     : TZQuery;     // Inserir pedido
    QrySQL     : TZQuery;     // Consultas diversas
    QryInsIPed : TZQuery;     // Inserir itens do pedido
    URLBase    : String;

    vIni        : TIniFile;
//    qryProdutos : string;
//    qryRotas    : string;
    procedure ChecaIniFile;
    procedure CarregaBanco;
    procedure Consultas;

    function  getInsertPedido : String;
    function  getInsertItemPedido : String;
    function  getCliente : String;
    function  qetClientes : String;
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
var
  // Respostas de consultas REST
  vRespPed   : IResponse;
  vRespItens : IResponse;
  vRespForma : IResponse;

  URLPed     : string;
  URLItem    : string;
  URLPut     : string;

  // Estruturas JSON
  vPedidos   : string;
  vItens     : string;
  vForma     : string;
  jPedidos   : TJSONData;
  jItens     : TJSONData;
  jForma     : TJSONData;
  // Campos do pedido
  pPedido    : string;
  pdtpedido  : string;
  pdataped   : string;
  pVendedor  : string;
  pCliente   : string;
  pNomCli    : string;
  pCnpjCli   : string;
  pTipo      : string;
  pFormPgto  : string;
  pObs       : string;
  pTotal     : string;
  // Campos do item pedido
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
  URLPut   := Trim(URLBase)+'convertido/';

  lblPasso1.Font.Bold := True;
  Application.ProcessMessages;

  vRespPed := TRequest.New.BaseURL(trim(URLPed))
    .AddHeader('Authorization', 'Basic Zml0dGVjbm9sb2dpYTpzdXBlcmNhZ2lmcmFnaWxpc3RjYXNwaWFsaWRvc28')
    .Accept('application/json')
    .Get;

  if (vRespPed.StatusCode = 200) and (trim(vRespPed.Content) <> '') then
  begin
    //ShowMessage(vResponse.Content);
    vPedidos := getJsonArray(vRespPed.Content);
    //ShowMessage(vPedidos);
    jPedidos := GetJSON(vPedidos);

    mtPedidos.Clear(False);
    mtPedidos.Close;
    mtPedidos.Active := true;
    mtPedidos.LoadFromJSON(jPedidos.AsJSON);

    mtPedidos.First;

    lblP1Ok.Visible     := True;
    lblPasso2.Font.Bold := True;
    Application.ProcessMessages;

    vCon.StartTransaction;

    while not mtPedidos.EOF do
    begin
      pPedido    := mtPedidos.FieldByName('id').AsString;
      pdtpedido  := mtPedidos.FieldByName('dtpedido').AsString;
      pVendedor  := mtPedidos.FieldByName('vendedor').AsString;
      pCliente   := mtPedidos.FieldByName('cliente').AsString;
      pTipo      := mtPedidos.FieldByName('tipo').AsString;
      pFormPgto  := mtPedidos.FieldByName('forma_pagamento').AsString;
      pObs       := mtPedidos.FieldByName('obs').AsString;
      pTotal     := mtPedidos.FieldByName('total').AsString;

      // Insere na base da retaguarda
      vSQL := getInsertPedido;

      // codigo do vendedor inicia o número do pedido
      // 25000122  -> vendedor 25 pedido 122
      //
      vNroPed := ((StrToInt(pVendedor) * 1000000) +  StrToInt(pPedido));

      vSQL := vSQL + '(' + IntToStr(vNroPed) +',';
      vSQL := vSQL + pCliente +',';
      vSQL := vSQL + pVendedor +',';
      // forma fixa 1
      vSQL := vSQL + '1 ' +',';
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
      end
      else
      begin
        pCnpjCli := Trim(QrySQL.FieldByName('CNPJ_CLI').AsString);
        pNomCli  := Trim(QrySQL.FieldByName('NOME_FANTASIA').AsString);
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
      vSQL := vSQL + Aspas(Trim(pObs)) + ',';
      vSQL := vSQL + '1, ';
      vSQL := vSQL + 'null, ';
      vSQL := vSQL + '0, ';
      vSQL := vSQL + 'null, ';
      vSQL := vSQL + 'null, ';
      vSQL := vSQL + 'null, ';
      vSQL := vSQL + 'null) ';

      //ShowMessage(vSQL);

      // Monta e executa insert
      QryIns.Close;
      QryIns.SQL.Clear;
      QryIns.SQL.Text := vSQL ;

      try
         QryIns.ExecSQL;
      except
        on e: Exception do
        begin
          raise Exception.Create('Erro ao atualizar base de pedidos mobile ' + Chr(13) + Chr(13) + E.Message );
        end;
      end;

      lblP2Ok.Visible     := True;
      Application.ProcessMessages;

      vRespItens := TRequest.New.BaseURL(trim(URLItem)+trim(pPedido))
          .AddHeader('Authorization', 'Basic Zml0dGVjbm9sb2dpYTpzdXBlcmNhZ2lmcmFnaWxpc3RjYXNwaWFsaWRvc28')
              .Accept('application/json')
                  .Get;

      if (vRespItens.StatusCode = 200) and (trim(vRespItens.Content) <> '') then
      begin

          //ShowMessage(vResponse.Content);
          vItens := getJsonArray(vRespItens.Content);
          //ShowMessage(vItens);
          jItens := GetJSON(vItens);

          mtItensPedido.Clear(False);
          mtItensPedido.Close;
          mtItensPedido.Active := true;
          mtItensPedido.LoadFromJSON(jItens.AsJSON);

          mtItensPedido.First;

          iOrdem := 0;

          while not mtItensPedido.EOF do
          begin

             iProduto    := mtItensPedido.FieldByName('produto').AsString;
             iQuantidade := mtItensPedido.FieldByName('quantidade').AsString;
             iUnitario   := mtItensPedido.FieldByName('unitario').AsString;
             iTotal      := mtItensPedido.FieldByName('total').AsString;
             iOrdem      := iOrdem + 1;

             vSQL := getInsertItemPedido;
             vSQL := vSQL + '( 0' + ', ';               // ID
             vSQL := vSQL + IntToStr(vNroPed) + ', ';   // ID_VENDA_CABECALHO
             vSQL := vSQL + Aspas(iProduto)+ ', ';      // ID_PRODUTO
             vSQL := vSQL + IntToStr(iOrdem)+ ', ';     // ITEM
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
               raise Exception.Create('Erro ao buscar dados do produto ' +
                                         Chr(13) + Chr(13) + E.Message);
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
             vSQL := vSQL + 'NULL'+ ')';                         // EXCLUIDO

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
                 raise Exception.Create('Erro ao atualizar base de itens de pedidos mobile ' +
                                              Chr(13) + Chr(13) + E.Message );
               end;
             end;

             mtItensPedido.Next;
          end;

      end;

      mtPedidos.Next;
    end;

    vCon.Commit;

    ShowMessage('Integração realizada');
    Application.Terminate;

  end;
end;

procedure TForm1.btnSairClick(Sender: TObject);
begin
  Application.Terminate;
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
    vCon.Protocol        := 'firebird-2.5';
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

  URLBase := vIni.ReadString('CLOUD', 'URLBase', 'Error');

  If Trim(URLBase) = 'Error' then
  begin
    raise Exception.Create('Erro ao carregar configuração da URL base, verifique a configuração');
  end;

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

    QrySQL := TZQuery.Create(nil);
    QrySQL.Connection := vCon;

end;

function TForm1.Aspas(cValue: String) : String;
begin
  result := Chr(39) + trim(cValue) + Chr(39);

end;

function TForm1.getCliente : String;
begin
   result := 'SELECT '+
             ' CNPJ_CLI, NOME_FANTASIA '  +
             'FROM CLIENTE WHERE COD_CLI = :COD_CLI';
end;

function TForm1.getVendedor : String;
begin
   result := 'SELECT COD_VEND FROM VENDEDOR WHERE COD_MOB = :COD_MOB';
end;

function TForm1.getInsertPedido : String;
begin
   result := 'INSERT INTO MB_VENDA_CABECALHOS '+
             ' (ID, ID_CLIENTE, ID_USUARIO,  ' +
             ' ID_FORM_PG, CNPJ_CPF_CLI, CLIENT, DATA_VENDA, VALOR_VENDA,' +
             ' DESCONTO, VALOR_FINAL, SINCRONIZADO, STATUS_VENDA, DATA_PED,' +
             ' OBS, ROTA, ENTREGUE, QTDE_DIAS, NOSSO_NUMERO, DATA_ENTREGUE,' +
             ' ROMANEIO, VENDA) VALUES ';
end;

function TForm1.getInsertItemPedido : String;
begin
  result := 'INSERT INTO MB_VENDA_DETALHES  '+
            ' (ID, ID_VENDA_CABECALHO, ID_PRODUTO, ITEM, DESC_PROD,'+
            ' UN, VALOR_UNITARIO, QUANTIDADE, TOTAL_ITEM, DESCONTO,'+
            ' VALOR_TOTAL, ST, SINCRONIZADO, DATA_PED, VL_DESCONTO,'+
            ' DEVOLVIDO, QUANTIDADE_DEV, EXCLUIDO) '+
            'VALUES  ';
end;

function TForm1.getProduto : String;
begin
   result := 'SELECT '+
             ' P.NOME_PRO, M.DESCRICAO ' +
             'FROM '+
             ' PRODUTO P, UNIDADE_MEDIDA M '+
             'WHERE '+
             '     P.COD_PRO = :COD_PRO '+
             ' AND M.CODIGO = P.CODIGO_UNIDADE_SAIDA';
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

function TForm1.qetClientes : String;
begin
  result :=' select  COD_CLI as id, '+
    'REPLACE(REPLACE(REPLACE(REPLACE(CNPJ_CLI,''.'''',''''),''/'',''''),''-'',''''),''_'','''') as cnpj_cpf, '+
    'NOME_CLI as razao, '+
    'coalesce(NOME_FANTASIA,NOME_CLI) as fantasia, '+
    'coalesce(ENDRES_CLI, ''***SEM ENDERECO***'') as endereco, '+
    'coalesce(NUMRES_CLI, ''S/N'') as nr, '+
    'CASE CODIGO_IBGE '+
    '  WHEN    2312304     THEN ''SAO BENEDITO'' '+
    '  WHEN    3503000     THEN ''ARAMINA'' '+
    '  WHEN    3505500     THEN ''BARRETOS'' '+
    '  WHEN    3505906     THEN ''BATATAIS'' '+
    '  WHEN    3506003     THEN ''BAURU'' '+
    '  WHEN    3506102     THEN ''BEBEDOURO'' '+
    '  WHEN    3508207     THEN ''BURITIZAL'' '+
    '  WHEN    3513108     THEN ''CRAVINHOS'' '+
    '  WHEN    3513207     THEN ''CRISTAIS PAULISTA'' '+
    '  WHEN    3516200     THEN ''FRANCA'' '+
    '  WHEN    3517406     THEN ''GUAIRA'' '+
    '  WHEN    3517703     THEN ''GUARA'' '+
    '  WHEN    3520103     THEN ''IGARAPAVA'' '+
    '  WHEN    3521309     THEN ''IPUA'' '+
    '  WHEN    3523701     THEN ''ITIRAPUA'' '+
    '  WHEN    3524105     THEN ''ITUVERAVA'' '+
    '  WHEN    3525409     THEN ''JERIQUARA'' '+
    '  WHEN    3529708     THEN ''MIGUELOPOLIS'' '+
    '  WHEN    3531902     THEN ''MORRO AGUDO'' '+
    '  WHEN    3533601     THEN ''NUPORANGA'' '+
    '  WHEN    3534302     THEN ''ORLANDIA'' '+
    '  WHEN    3536307     THEN ''PATROCINIO PAULISTA'' '+
    '  WHEN    3537008     THEN ''PEDREGULHO'' '+
    '  WHEN    3540200     THEN ''PONTAL'' '+
    '  WHEN    3542701     THEN ''RESTINGA'' '+
    '  WHEN    3543402     THEN ''RIBEIRAO PRETO'' '+
    '  WHEN    3543600     THEN ''RIFAINA'' '+
    '  WHEN    3544905     THEN ''SALES OLIVEIRA'' '+
    '  WHEN    3549409     THEN ''SAO JOAQUIM DA BARRA'' '+
    '  WHEN    3549508     THEN ''SAO JOSE DA BELA VISTA'' '+
    '  WHEN    3551504     THEN ''SERRANA'' '+
    '  WHEN    3554409     THEN ''TERRA ROXA'' '+
    '  WHEN    3556800     THEN ''VIRADOURO'' '+
    '  WHEN    4216503     THEN ''SAO JOAQUIM'' '+
    '  WHEN    4219309     THEN ''VIDEIRA'' '+
    '  ELSE ''ORLANDIA'' '+
    'END AS compl, ' +
    'coalesce(BAIRES_CLI, ''***SEM BAIRRO***'') as bairro,  '+
    'CEPRES_CLI as cep, ' +
    'TELRES_CLI as fone, ' +
    'CELULAR_CLI as celular, ' +
    'CASE CODIGO_IBGE ' +
    '  WHEN    2312304     THEN  1  ' +     //--    SAO BENEDITO
    '  WHEN    3503000     THEN  2  ' +     //--    ARAMINA
    '  WHEN    3505500     THEN  3  ' +     //--    BARRETOS
    '  WHEN    3505906     THEN  4  ' +     //--    BATATAIS
    '  WHEN    3506003     THEN  5  ' +     //--    BAURU
    '  WHEN    3506102     THEN  6  ' +     //--    BEBEDOURO
    '  WHEN    3508207     THEN  7  ' +     //--    BURITIZAL
    '  WHEN    3513108     THEN  8  ' +     //--    CRAVINHOS
    '  WHEN    3513207     THEN  9  ' +     //--    CRISTAIS PAULISTA
    '  WHEN    3516200     THEN 10  ' +     //--    FRANCA
    '  WHEN    3517406     THEN 11  ' +     //--    GUAIRA
    '  WHEN    3517703     THEN 12  ' +     //--    GUARA
    '  WHEN    3520103     THEN 13  ' +     //--    IGARAPAVA
    '  WHEN    3521309     THEN 14  ' +     //--    IPUA
    '  WHEN    3523701     THEN 15  ' +     //--    ITIRAPUA
    '  WHEN    3524105     THEN 16  ' +     //--    ITUVERAVA
    '  WHEN    3525409     THEN 17  ' +     //--    JERIQUARA
    '  WHEN    3529708     THEN 18  ' +     //--    MIGUELOPOLIS
    '  WHEN    3531902     THEN 19  ' +     //--    MORRO AGUDO
    '  WHEN    3533601     THEN 20  ' +     //--    NUPORANGA
    '  WHEN    3534302     THEN 21  ' +     //--    ORLANDIA
    '  WHEN    3536307     THEN 22  ' +     //--    PATROCINIO PAULISTA
    '  WHEN    3537008     THEN 23  ' +     //--    PEDREGULHO
    '  WHEN    3540200     THEN 24  ' +     //--    PONTAL
    '  WHEN    3542701     THEN 25  ' +     //--    RESTINGA
    '  WHEN    3543402     THEN 26  ' +     //--    RIBEIRAO PRETO
    '  WHEN    3543600     THEN 27  ' +     //--    RIFAINA
    '  WHEN    3544905     THEN 28  ' +     //--    SALES OLIVEIRA
    '  WHEN    3549409     THEN 29  ' +     //--    SAO JOAQUIM DA BARRA
    '  WHEN    3549508     THEN 30  ' +     //--    SAO JOSE DA BELA VISTA
    '  WHEN    3551504     THEN 31  ' +     //--    SERRANA
    '  WHEN    3554409     THEN 32  ' +     //--    TERRA ROXA
    '  WHEN    3556800     THEN 33  ' +     //--    VIRADOURO
    '  WHEN    4216503     THEN 34  ' +     //--    SAO JOAQUIM
    '  WHEN    4219309     THEN 35  ' +     //--    VIDEIRA
    '  ELSE 21  ' +
    'END AS rota, ' +
    'DATACADASTRO_CLI as createdat, ' +
    'NULL as updatedat ' +
    'from cliente ' +
    'where ' +
    '    trim(nome_cli) <> ''''  ' +
    'and REPLACE(REPLACE(REPLACE(REPLACE(CNPJ_CLI,''.'''',''''),''/'',''''),''-'',''''),''_'','''')  <> '''' '+
    'and REPLACE(REPLACE(REPLACE(REPLACE(CNPJ_CLI,''.'''',''''),''/'',''''),''-'',''''),''_'','''')  <> ''00000000000000'' '+
    'and cod_cli <> 1 ' +
    'and ativo_cli = ''S'' ' +
    'order by 1';
end;

end.

