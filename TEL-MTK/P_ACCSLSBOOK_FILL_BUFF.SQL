create or replace procedure P_ACCSLSBOOK_FILL_BUFF
(
  nCOMPANY              in number,            -- регистрационный номер организации
  nIDENT                in number,            -- идентификатор процесса
  nRN                   in number,            -- регистрационный номер записи книги продаж
  dDATE                 in date,              -- дата ХО
  sRULE                 in varchar2,          -- мнемокод правила отработки
  nUSE_INDATE           in number,            -- признак использования даты включения
  sLINK_TYPE            in varchar2,          -- тип отработки (связи), через ';' пустой - все, 0 - бухгалтерский, 1 - налоговый
  nCONFIRM              in number,            -- расчёт с подтверждением
  nCALC_IN_SERVER       out number            -- нужно ли расчитывать формулу на клиенте
)
as
  nCRN                  PKG_STD.tREF;
  nJUR_PERS             PKG_STD.tREF;
  nRULE                 PKG_STD.tREF;
  nCURRENCY             PKG_STD.tREF;
  nRN_M                 PKG_STD.tREF;
  sOPER_NUMB            PKG_STD.tSTRING;
  dOPER_DATE            date;
  nAGN_FROM             PKG_STD.tREF;
  nAGN_TO               PKG_STD.tREF;
  nRN_S                 PKG_STD.tREF;
  nMAX_RN               PKG_STD.tREF;
  sNOMEN                DICANLS.ANL_NUMBER%type;
  sNOMEN_NAME           DICANLS.ANL_NAME%type;
  nANL_LEVEL            PKG_STD.tNUMBER;
  nANL_RN               PKG_STD.tREF;
  nNEW_ANL_RN           PKG_STD.tREF;

  nANALYTIC_DEBIT1      PKG_STD.tREF;
  nANALYTIC_DEBIT2      PKG_STD.tREF;
  nANALYTIC_DEBIT3      PKG_STD.tREF;
  nANALYTIC_DEBIT4      PKG_STD.tREF;
  nANALYTIC_DEBIT5      PKG_STD.tREF;
  nANALYTIC_CREDIT1     PKG_STD.tREF;
  nANALYTIC_CREDIT2     PKG_STD.tREF;
  nANALYTIC_CREDIT3     PKG_STD.tREF;
  nANALYTIC_CREDIT4     PKG_STD.tREF;
  nANALYTIC_CREDIT5     PKG_STD.tREF;

  nUSER_PROC_TMP        PKG_STD.tREF;
  nCALC_IN_SERVER_TMP   number;
  nCALC_PLACE           number;

  /* документ-подтверждение */
  nVDOC_TYPE            PKG_STD.tREF;
  sVDOC_NUMB            PKG_STD.tSTRING;
  dVDOC_DATE            date;
  /* документ-сопровождения */
  nEDOC_TYPE            PKG_STD.tREF;
  sEDOC_NUMB            PKG_STD.tSTRING;
  dEDOC_DATE            date;

  /* настройки */
  nOPT_DOC_TYPE         PKG_STD.tREF;
  sOPT_DOC_TYPE         PKG_STD.tSTRING;
  nGLUE_PREFNUMB        number;


  type tLINK is     record
  (
    LINK_TYPE       PKG_STD.tNUMBER,
    ACTION          PKG_STD.tSTRING
  );

  type tLINK_TABLE  is table of tLINK;
  tLINK_TYPES       tLINK_TABLE := tLINK_TABLE();

begin
  /* считывание записи книги продаж */
  P_ACCSLSBOOK_EXISTS(nCOMPANY, nRN, nCRN, nJUR_PERS);

  /* поиск правила отработки */
  FIND_ACCSBOOKOMDL_CODE(0, 0, nCOMPANY, sRULE, nRULE);

  /* поиск базовой валюты */
  FIND_CURRENCY_BASE(nCOMPANY, nCURRENCY);

  /* установка типов связи и действий для них*/
  if ((STRIN('0',sLINK_TYPE,';') = 1) or (rtrim(sLINK_TYPE) is null)) then
    tLINK_TYPES.EXTEND;
    tLINK_TYPES(tLINK_TYPES.LAST).LINK_TYPE := 0;
    tLINK_TYPES(tLINK_TYPES.LAST).ACTION    := 'ACCSLSBOOK_FILL_BUFF';
  end if;
  
  if (STRIN('1',sLINK_TYPE,';') = 1) or (rtrim(sLINK_TYPE) is null) then
    tLINK_TYPES.EXTEND;
    tLINK_TYPES(tLINK_TYPES.LAST).LINK_TYPE := 1;
    tLINK_TYPES(tLINK_TYPES.LAST).ACTION    := 'ACCSLSBOOK_FILL_BUFF_TAX';
  end if;

  /* определение RN последней строки спецификации книги продаж */
  select max(RN) into nMAX_RN from ACCSLSBOOKSP where PRN = nRN;

  /* буфер для наследования документов: конструктор */
  PKG_INHIER.CONSTRUCTOR(nCOMPANY, nIDENT);

  /* считываем настройки */
  /* тип документа исходящих счет-фактур */
  sOPT_DOC_TYPE := GET_OPTIONS_STR( 'AccountFactOutputDocType', nCOMPANY );
  FIND_DOCTYPES_CODE_EX( 0, 1, nCOMPANY, sOPT_DOC_TYPE, nOPT_DOC_TYPE );
  /* склеивание префикса и номера */
  nGLUE_PREFNUMB := GET_OPTIONS_NUM( 'GluePrefNumb', nCOMPANY );


  /* по учётам */
  for J in tLINK_TYPES.FIRST..tLINK_TYPES.LAST loop

    nRN_M := null;

    /* подготовка к привязке документа */
    PKG_INHIER.PREP_LINK(nIDENT);

    /* предварительная проверка прав доступа */
    PKG_ENV.ACCESS(nCOMPANY, null, nCRN, nJUR_PERS, 'AccountSalesBook', tLINK_TYPES(J).ACTION);

    /* регистрация параметров раздела входного (отрабатываемого) документа */
    PKG_INHIER.SET_IN_UNIT(nIDENT, 0, 'AccountSalesBook', tLINK_TYPES(J).LINK_TYPE, tLINK_TYPES(J).ACTION, 'ACCSLSBOOK');
    PKG_INHIER.SET_IN_UNIT(nIDENT, 1, 'AccountSalesBookSpec');
    /* регистрация выходного раздела */
    PKG_INHIER.SET_OUT_UNIT(nIDENT, 0, 'EconomicOperations');
    PKG_INHIER.SET_OUT_UNIT(nIDENT, 1, 'EconomicOperationsSpecs');

    /* отбор правил для книги продаж */
    for rec in
    ( select
        B.RN                B_RN,
        BS.RN               BS_RN,
        B.JUR_PERS          JUR_PERS,
        B.DATE_IN           DATE_IN,
        ATD.TYPE            ACDB_LINK_TYPE,
        ATC.TYPE            ACCR_LINK_TYPE,
        B.VENDOR            VENDOR,
        B.CUSTOMER          CUSTOMER,
        B.DOC_DATE          DOC_DATE,
        ltrim(B.DOC_PREF)   DOC_PREF,
        ltrim(B.DOC_NUMB)   DOC_NUMB,
        B.BDOC_TYPE         BDOC_TYPE,
        B.BDOC_NUMB         BDOC_NUMB,
        B.BDOC_DATE         BDOC_DATE,
        B.VDOC_TYPE         VDOC_TYPE,
        B.VDOC_NUMB         VDOC_NUMB,
        B.VDOC_DATE         VDOC_DATE,
        B.INDOC_DATE        INDOC_DATE,
        B.INDOC_NUMB        INDOC_NUMB,
        B.BOOK_TYPE         BOOK_TYPE,
        MS.RN               MS_RN,
        MS.TOTAL_EO         TOTAL_EO,
        MS.ACCOUNT_DEBIT    ACCOUNT_DEBIT,
        MS.ANALYTIC_DEBIT1  ANALYTIC_DEBIT1,
        MS.ANALYTIC_DEBIT2  ANALYTIC_DEBIT2,
        MS.ANALYTIC_DEBIT3  ANALYTIC_DEBIT3,
        MS.ANALYTIC_DEBIT4  ANALYTIC_DEBIT4,
        MS.ANALYTIC_DEBIT5  ANALYTIC_DEBIT5,
        MS.DOC_NOMEN_DEBIT  DOC_NOMEN_DEBIT,
        MS.ACCOUNT_CREDIT   ACCOUNT_CREDIT,
        MS.ANALYTIC_CREDIT1 ANALYTIC_CREDIT1,
        MS.ANALYTIC_CREDIT2 ANALYTIC_CREDIT2,
        MS.ANALYTIC_CREDIT3 ANALYTIC_CREDIT3,
        MS.ANALYTIC_CREDIT4 ANALYTIC_CREDIT4,
        MS.ANALYTIC_CREDIT5 ANALYTIC_CREDIT5,
        MS.DOC_NOMEN_CREDIT DOC_NOMEN_CREDIT,
        MS.FORMULA_SUM      FORMULA_SUM,
        MS.ORDER_RN,
        BS.NOMEN            NOMEN,
        BS.SUM_NDS          SUM_NDS,
        decode(tLINK_TYPES(J).LINK_TYPE, 0, M.OPER_CRN,        1, M.TAX_OPER_CRN)   OPER_CRN,
        decode(tLINK_TYPES(J).LINK_TYPE, 0, M.PREF,            1, M.TAX_PREF)       OPER_PREF,
        decode(tLINK_TYPES(J).LINK_TYPE, 0, M.CONTENT,         1, M.TAX_CONTENT)    CONTENT,
        decode(tLINK_TYPES(J).LINK_TYPE, 0, M.MARK,            1, M.TAX_MARK)       SPEC_MARK,
        decode(tLINK_TYPES(J).LINK_TYPE, 0, M.AGENT_SIGN,      1, M.TAX_AGENT_SIGN) AGENT_SIGN,
        decode(tLINK_TYPES(J).LINK_TYPE, 0, M.DOC_TYPE,        1, M.TAX_DOC_TYPE)   MDL_DOC_TYPE,
        decode(tLINK_TYPES(J).LINK_TYPE, 0, M.FILL_VDOC,       1, M.TAX_FILL_VDOC)  FILL_VDOC,
        decode(tLINK_TYPES(J).LINK_TYPE, 0, M.FILL_EDOC,       1, M.TAX_FILL_EDOC)  FILL_EDOC,
        decode(MS.DOC_BALUNIT_DEBIT,     0, MS.BALUNIT_DEBIT,  1, BS.BALUNIT)       BALUNIT_DEBIT,
        decode(MS.DOC_BALUNIT_CREDIT,    0, MS.BALUNIT_CREDIT, 1, BS.BALUNIT)       BALUNIT_CREDIT,
        M.CALC_PLACE,
        MS.USER_PROC
      from
        ACCSBOOKOMDL   M,
        ACCSBOOKOMDLSP MS,
        ACCSLSBOOK    B,
        ACCSLSBOOKSP  BS,
        DICACCS        ACD,
        DICACCS        ACC,
        ACCTYPES       ATD,
        ACCTYPES       ATC,
        DICNOMNS       N
      where M.RN              = nRULE
        and MS.PRN            = M.RN
        and B.CANCEL_DATE is null
        and B.RN              = nRN
        and BS.PRN            = B.RN
        and MS.ACCOUNT_DEBIT  = ACD.RN(+)
        and MS.ACCOUNT_CREDIT = ACC.RN(+)
        and ACD.ACCTYPES      = ATD.RN(+)
        and ACC.ACCTYPES      = ATC.RN(+)
        and BS.NOMEN          = N.RN(+)
        -- условия
        and (MS.VENDOR is null or MS.VENDOR = B.VENDOR)
        and (MS.VENDOR_GRP is null or
            (B.VENDOR is not null and B.VENDOR in (select AGENT from UNAGGRSP where PRN = MS.VENDOR_GRP)))
        and (MS.CUSTOMER is null or MS.CUSTOMER = B.CUSTOMER)
        and (MS.CUSTOMER_GRP is null or
            (B.CUSTOMER is not null and B.CUSTOMER in (select AGENT from UNAGGRSP where PRN = MS.CUSTOMER_GRP)))
        and ((MS.TYPE_NOM = 0)
             or (MS.TYPE_NOM in (1, 2, 3) and MS.TYPE_NOM = N.NOMEN_TYPE)
             or (MS.TYPE_NOM = 4 and BS.NOMEN is null))
        and (MS.NOMEN_GRP is null or MS.NOMEN_GRP = N.GROUP_CODE)
        and (MS.RATE_NDS_FROM is null or MS.RATE_NDS_FROM is not null and MS.RATE_NDS_FROM <= BS.RATE_NDS)
        and (MS.RATE_NDS_TO is null or MS.RATE_NDS_TO is not null and MS.RATE_NDS_TO >= BS.RATE_NDS)
        and (MS.BALUNIT is null or MS.BALUNIT = BS.BALUNIT)
        and (MS.BOOK_TYPE = 0 or (MS.BOOK_TYPE = B.BOOK_TYPE + 1))
        and not exists
        (
          select null
            from DOCLINKS L
            where L.IN_DOCUMENT = B.RN
              and L.LINK_TYPE = tLINK_TYPES(J).LINK_TYPE
              and L.OUT_UNITCODE = 'EconomicOperations'
              and L.IN_UNITCODE = 'AccountSalesBook'
        )
      order by TOTAL_EO, BS_RN, MS_RN
    )loop

      -- учет
      if (rec.ACDB_LINK_TYPE = tLINK_TYPES(J).LINK_TYPE) or
         (rec.ACCR_LINK_TYPE = tLINK_TYPES(J).LINK_TYPE)
      then
        /* установка входного документа */
        PKG_INHIER.SET_IN_DOC_EX(nIDENT, 0, nRN, nCRN, nJUR_PERS);
        PKG_INHIER.SET_IN_DOC(nIDENT, 1, rec.BS_RN);

        /* создание заголовка */
        if (nRN_M is null) then
          /* генерация номера ХО */
          P_ECOPRBUF_GETNEXTNUMB(nCOMPANY, nIDENT, rec.OPER_PREF, sOPER_NUMB);

          /* дата ХО */
          if (nUSE_INDATE = 1) then
            dOPER_DATE := rec.DATE_IN;
          else
            dOPER_DATE := dDATE;
          end if;

          /* контрагенты */
          if (rec.AGENT_SIGN = 0) then
            nAGN_FROM := rec.VENDOR;
            nAGN_TO   := rec.CUSTOMER;
          elsif (rec.AGENT_SIGN = 1) then
            nAGN_FROM := rec.CUSTOMER;
            nAGN_TO   := rec.VENDOR;
          else
            nAGN_FROM := rec.CUSTOMER;
            nAGN_TO   := rec.CUSTOMER;
          end if;

          /* документ-подтверждения */
          if rec.FILL_VDOC = 1 then
            /* если в правиле нет, берем из настройки */
            if rec.MDL_DOC_TYPE is null then
              nVDOC_TYPE := nOPT_DOC_TYPE;
            else
              nVDOC_TYPE := rec.MDL_DOC_TYPE;
            end if;
            /* для строрно и возврата аванса берем номер и дату счета-фактуры поставщика   */
            if rec.BOOK_TYPE in (2,3) then
              sVDOC_NUMB := rec.INDOC_NUMB;
              dVDOC_DATE := rec.INDOC_DATE;
            else
              if nGLUE_PREFNUMB = 1 then
                sVDOC_NUMB := substr(rtrim(rec.DOC_PREF)||rtrim(rec.DOC_NUMB),1,20);
              else
                sVDOC_NUMB := substr(rtrim(rec.DOC_NUMB),1,20);
              end if;
              dVDOC_DATE := rec.DOC_DATE;
            end if;
          elsif rec.FILL_VDOC = 2 then
            nVDOC_TYPE := rec.VDOC_TYPE;
            sVDOC_NUMB := rec.VDOC_NUMB;
            dVDOC_DATE := rec.VDOC_DATE;
          else
            nVDOC_TYPE := null;
            sVDOC_NUMB := null;
            dVDOC_DATE := null;
          end if;

          /* документ-сопровождения */
          if rec.FILL_EDOC = 1 then
            /* если в правиле нет, берем из настройки */
            if rec.MDL_DOC_TYPE is null then
              nEDOC_TYPE := nOPT_DOC_TYPE;
            else
              nEDOC_TYPE := rec.MDL_DOC_TYPE;
            end if;

            /* для строрно и возврата аванса берем номер и дату счета-фактуры поставщика   */
            if rec.BOOK_TYPE in (2,3) then
              sEDOC_NUMB := rec.INDOC_NUMB;
              dEDOC_DATE := rec.INDOC_DATE;
            else
              if nGLUE_PREFNUMB = 1 then
                sEDOC_NUMB := substr(rtrim(rec.DOC_PREF)||rtrim(rec.DOC_NUMB),1,20);
              else
                sEDOC_NUMB := substr(rtrim(rec.DOC_NUMB),1,20);
              end if;
              dEDOC_DATE := rec.DOC_DATE;
            end if;
          else
            nEDOC_TYPE := null;
            sEDOC_NUMB := null;
            dEDOC_DATE := null;
          end if;

          /* создание заголовка ХО */
          P_ECOPRBUF_BASE_INSERT(nCOMPANY, nIDENT, rec.OPER_CRN, rec.JUR_PERS, rec.OPER_PREF, sOPER_NUMB,
            rec.CONTENT, dOPER_DATE, rec.SPEC_MARK, rec.BDOC_TYPE, rec.BDOC_NUMB, rec.BDOC_DATE, nVDOC_TYPE,
            sVDOC_NUMB, dVDOC_DATE, nAGN_FROM, nAGN_TO, null, nEDOC_TYPE, sEDOC_NUMB, dEDOC_DATE, nRN_M);

          /* установка буферного документа */
          PKG_INHIER.SET_BUFF_DOC(nIDENT, 0, nRN_M);
        end if;

        /* формирование проводок */
        if (rec.TOTAL_EO = 0 or rec.TOTAL_EO = 1 and rec.BS_RN = nMAX_RN) then

          /* для формирования в конце */
          if (rec.TOTAL_EO = 1) then
            rec.SUM_NDS := 0;
          end if;

          /* заполнение аналитики - номенклатор */
          if (rec.NOMEN is not null) then

            /* считывание мнемокода и наименования номенклатуры */
            select NOMEN_CODE, NOMEN_NAME
            into   sNOMEN, sNOMEN_NAME
            from   DICNOMNS
            where  RN = rec.NOMEN;

            /* счет дебет */
            if (rec.DOC_NOMEN_DEBIT = 1) then
              nANL_LEVEL := 1;
              loop
                if F_ANLPLANUNITS_GET_UNITCODE(rec.ACCOUNT_DEBIT,nANL_LEVEL) = 'Nomenclator' or
                  nANL_LEVEL = 6 then EXIT;
                end if;
                nANL_LEVEL := nANL_LEVEL + 1;
              end loop;

              if (nANL_LEVEL < 6) then /* раздел назначен */
                /* есть ли такой аналитический счет? */
                begin
                  select RN
                  into   nANL_RN
                  from   DICANLS
                  where  PRN = rec.ACCOUNT_DEBIT and
                        ANL_LEVEL = nANL_LEVEL and DOC_RN = rec.NOMEN;
                  /* есть такой счет */
                  /* указано ли в заголовке документа значение аналитического счета этого уровня? */
                  if (rec.ANALYTIC_DEBIT1 = nANL_RN or
                      rec.ANALYTIC_DEBIT2 = nANL_RN or
                      rec.ANALYTIC_DEBIT3 = nANL_RN or
                      rec.ANALYTIC_DEBIT4 = nANL_RN or
                      rec.ANALYTIC_DEBIT5 = nANL_RN) then /* указано */
                      /* оставляем значения на месте, ничего не меняя */
                      null;
                  else /* не указано */
                    /* берем номер аналитического счета из спецификации документа */
                    if nANL_LEVEL = 1 then rec.ANALYTIC_DEBIT1 := nANL_RN;
                    elsif nANL_LEVEL = 2 then rec.ANALYTIC_DEBIT2 := nANL_RN;
                    elsif nANL_LEVEL = 3 then rec.ANALYTIC_DEBIT3 := nANL_RN;
                    elsif nANL_LEVEL = 4 then rec.ANALYTIC_DEBIT4 := nANL_RN;
                    elsif nANL_LEVEL = 5 then rec.ANALYTIC_DEBIT5 := nANL_RN;
                    end if;
                  end if;
                exception
                  /* нет такого счета - создаем */
                  when NO_DATA_FOUND then
                    P_DICANLS_BASE_INSERT(nCOMPANY,rec.ACCOUNT_DEBIT, nANL_LEVEL,
                      sNOMEN,sNOMEN_NAME,null,sNOMEN,sNOMEN_NAME,rec.NOMEN,0,0,
                      null/*nEXPSTRUCT*/,null/*nINCOMECLASS*/,null/*nFINSOURCE*/,
                      nNEW_ANL_RN);
                    /* пишем новый аналитический счет на нужное место */
                    if nANL_LEVEL = 1 then rec.ANALYTIC_DEBIT1 := nNEW_ANL_RN;
                    elsif nANL_LEVEL = 2 then rec.ANALYTIC_DEBIT2 := nNEW_ANL_RN;
                    elsif nANL_LEVEL = 3 then rec.ANALYTIC_DEBIT3 := nNEW_ANL_RN;
                    elsif nANL_LEVEL = 4 then rec.ANALYTIC_DEBIT4 := nNEW_ANL_RN;
                    elsif nANL_LEVEL = 5 then rec.ANALYTIC_DEBIT5 := nNEW_ANL_RN;
                    end if;
                end;
              end if;
            end if;
   
            /* счет кредит */
            if (rec.DOC_NOMEN_CREDIT = 1) then
              nANL_LEVEL := 1;
              loop
                if F_ANLPLANUNITS_GET_UNITCODE(rec.ACCOUNT_CREDIT,nANL_LEVEL) = 'Nomenclator' or
                  nANL_LEVEL = 6 then EXIT;
                end if;
                nANL_LEVEL := nANL_LEVEL + 1;
              end loop;

              if (nANL_LEVEL < 6) then /* раздел назначен */
                /* есть ли такой аналитический счет? */
                begin
                  select RN
                  into   nANL_RN
                  from   DICANLS
                  where  PRN = rec.ACCOUNT_CREDIT and
                        ANL_LEVEL = nANL_LEVEL and DOC_RN = rec.NOMEN;
                  /* есть такой счет */
                  /* указано ли в заголовке документа значение аналитического счета этого уровня? */
                  if (rec.ANALYTIC_CREDIT1 = nANL_RN or
                      rec.ANALYTIC_CREDIT2 = nANL_RN or
                      rec.ANALYTIC_CREDIT3 = nANL_RN or
                      rec.ANALYTIC_CREDIT4 = nANL_RN or
                      rec.ANALYTIC_CREDIT5 = nANL_RN) then /* указано */
                      /* оставляем значения на месте, ничего не меняя */
                      null;
                  else /* не указано */
                    /* берем номер аналитического счета из спецификации документа */
                    if nANL_LEVEL = 1 then rec.ANALYTIC_CREDIT1 := nANL_RN;
                    elsif nANL_LEVEL = 2 then rec.ANALYTIC_CREDIT2 := nANL_RN;
                    elsif nANL_LEVEL = 3 then rec.ANALYTIC_CREDIT3 := nANL_RN;
                    elsif nANL_LEVEL = 4 then rec.ANALYTIC_CREDIT4 := nANL_RN;
                    elsif nANL_LEVEL = 5 then rec.ANALYTIC_CREDIT5 := nANL_RN;
                    end if;
                  end if;
                exception
                  /* нет такого счета - создаем */
                  when NO_DATA_FOUND then
                    P_DICANLS_BASE_INSERT(nCOMPANY,rec.ACCOUNT_CREDIT,nANL_LEVEL,
                      sNOMEN,sNOMEN_NAME,null,sNOMEN,sNOMEN_NAME,rec.NOMEN,0,0,
                      null/*nEXPSTRUCT*/,null/*nINCOMECLASS*/,null/*nFINSOURCE*/,
                      nNEW_ANL_RN);
                    /* пишем новый аналитический счет на нужное место */
                    if nANL_LEVEL = 1 then rec.ANALYTIC_CREDIT1 := nNEW_ANL_RN;
                    elsif nANL_LEVEL = 2 then rec.ANALYTIC_CREDIT2 := nNEW_ANL_RN;
                    elsif nANL_LEVEL = 3 then rec.ANALYTIC_CREDIT3 := nNEW_ANL_RN;
                    elsif nANL_LEVEL = 4 then rec.ANALYTIC_CREDIT4 := nNEW_ANL_RN;
                    elsif nANL_LEVEL = 5 then rec.ANALYTIC_CREDIT5 := nNEW_ANL_RN;
                    end if;
                end;
              end if;
            end if;
          end if;
 
          /* переопределение аналитики дебет (свойства документов) */
          P_DICANLS_SEL_ANALYTIC_BY_PROP( rec.B_RN,'AccountSalesBook',rec.BS_RN,'AccountSalesBookSpec',null,null,
                                          rec.ACCOUNT_DEBIT,
                                          rec.ANALYTIC_DEBIT1, rec.ANALYTIC_DEBIT2, rec.ANALYTIC_DEBIT3,
                                          rec.ANALYTIC_DEBIT4, rec.ANALYTIC_DEBIT5,
                                          nANALYTIC_DEBIT1, nANALYTIC_DEBIT2, nANALYTIC_DEBIT3,
                                          nANALYTIC_DEBIT4, nANALYTIC_DEBIT5 );

          /* переопределение аналитики кредит (свойства документов) */
          P_DICANLS_SEL_ANALYTIC_BY_PROP( rec.B_RN,'AccountSalesBook',rec.BS_RN,'AccountSalesBookSpec',null,null,
                                          rec.ACCOUNT_CREDIT,
                                          rec.ANALYTIC_CREDIT1, rec.ANALYTIC_CREDIT2, rec.ANALYTIC_CREDIT3,
                                          rec.ANALYTIC_CREDIT4, rec.ANALYTIC_CREDIT5,
                                          nANALYTIC_CREDIT1, nANALYTIC_CREDIT2, nANALYTIC_CREDIT3,
                                          nANALYTIC_CREDIT4, nANALYTIC_CREDIT5 );

          if (rec.CALC_PLACE = 1) then
            nUSER_PROC_TMP := rec.USER_PROC;
          else
            nUSER_PROC_TMP := null;
          end if;

          nCALC_PLACE := rec.CALC_PLACE;

          /* базовое добавление проводки */
          P_SPECSBUF_BASE_INSERT_EX(nCOMPANY, nIDENT, nRN_M, rec.OPER_CRN, dOPER_DATE,
            rec.BALUNIT_DEBIT, rec.ACCOUNT_DEBIT, nANALYTIC_DEBIT1, nANALYTIC_DEBIT2,
            nANALYTIC_DEBIT3, nANALYTIC_DEBIT4, nANALYTIC_DEBIT5,
            rec.BALUNIT_CREDIT, rec.ACCOUNT_CREDIT, nANALYTIC_CREDIT1, nANALYTIC_CREDIT2,
            nANALYTIC_CREDIT3, nANALYTIC_CREDIT4, nANALYTIC_CREDIT5,
            nCURRENCY, null, null, null, rec.FORMULA_SUM, null, rec.SUM_NDS, rec.SUM_NDS,
            0, 0, 0, 0, 0, 0, 0, 0, null, null, null, null, null, null, null, null, null, null,
            rec.BS_RN, rec.B_RN, null,  rec.ORDER_RN, null, nUSER_PROC_TMP, nRN_S);

          /* установка буферного документа */
          PKG_INHIER.SET_BUFF_DOC(nIDENT, 1, nRN_S);

          /* привязка входного документа к буферному */
          PKG_INHIER.LINK_IN(nIDENT);
        end if;
      end if;
    end loop; -- rec
  end loop; -- J


  /* Проверка места расчёта формулы*/
  if (nCALC_PLACE = 1) then
    P_ECONOPRS_CALC_BUFF_IN_SERV ( nCOMPANY, nIDENT, nRN, nCALC_IN_SERVER_TMP );
  end if; -- Проверка места расчёта формулы

  /* расчёт на сервере без подтверждения */
  if nCALC_PLACE = 1 and nCONFIRM = 0 then
    P_ACCSLSBOOK_REPLACE(nCOMPANY, nIDENT, 1);
  end if;

  nCALC_IN_SERVER := nCALC_PLACE;
end;
