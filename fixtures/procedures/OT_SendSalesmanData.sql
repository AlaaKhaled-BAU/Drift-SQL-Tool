USE [Olives_BO]
GO
/****** Object:  StoredProcedure [dbo].[OT_SendSalesmanData]    Script Date: 23/09/2026 8:45:28 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
--select * from osfa_DB..OT_OrderHistoryHF

--OT_SendCompData 1
--5

ALTER PROCEDURE [dbo].[OT_SendSalesmanData] -- [dbo].[OT_SendSalesmanData] 290 , 109
--
	@CompNo int ,
	@SalesmanNo int  ,
	@SendDate smalldatetime = null
	
AS
BEGIN

--set @SendDate = '2017-01-31'
if @SendDate is null
	SET @SendDate = DATEADD(DAY, 0, DATEDIFF(DAY, 0, GetDate())) 
	SET @SendDate = DATEADD(DAY, 0, DATEDIFF(DAY, 0, @SendDate)) 

	DELETE FROM [OSFA_DB].[dbo].[OT_SalesmanMF] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo

	DECLARE @FromDate smalldatetime
	SET @FromDate = DATEADD(M,-6, @SendDate)

	DECLARE @RetInvDate smalldatetime
	SET @RetInvDate = DATEADD(M,-5, @SendDate)

	DECLARE @Year smallint
	DECLARE @FromMonth smallint
	DECLARE @ToMonth smallint
	Declare @Err nvarchar (100)
	Declare @StoreNo nvarchar (200)
	Declare @Ref2 smallint 

	SET @Year = Year(@SendDate)
	SET @FromMonth = Month(@SendDate)
	SET @ToMonth = Month(@SendDate)

	DECLARE @FirstDayInMonthDate smalldatetime = cast(cast(Year(@SendDate) as varchar(4)) + '-' + cast(Month(@SendDate) as varchar(2)) + '-01' as smalldatetime)

	DECLARE @PositionsID int
	DECLARE @SalesmanGroupID int
	DECLARE @IsUpdatedStock bit
	DECLARE @ClientActive smallint
	DECLARE @CalcItemBalance bit
	DECLARE @SerialType int
	DECLARE @SalespersonReference2 nvarchar(20)
	DECLARE @LockOnSendData bit
	DECLARE @ItemCategLevel smallint
	DECLARE @UseRangePrice bit
	DECLARE @SalesPersonType int
	Declare @IsMakeOrder bit
	Declare @IsMakeOrderOnly bit
	declare @IsMakeInvoiceAndOrder bit
	DECLARE @SalesmanPromGroup int
	DECLARE @SalesmanCarID int
	declare @AllowReplacement bit 
	Declare @IsMakeInvoice bit
	Declare @IsMakeReturnOrder bit
	 
	SELECT @ClientActive = ClientID  FROM ClientsActive WHERE (CompanyID = @CompNo)


	IF (@ClientActive=123 and @SalesPersonType=7) or @ClientActive = 161
	BEGIN 

	Update TransactionsHeaders set PostedToERP=1 
	where TransactionsHeaders.CompanyID=@CompNo and SalesPersonID=@SalesmanNo and ISNULL (PostedToERP,0)=0

	END
 


	
	if @ClientActive=38 and @SalesmanNo in(33,36,13)
	begin
	SET @RetInvDate = DATEADD(M,-4, @SendDate)
	end

	SELECT @PositionsID = PositionID, @IsUpdatedStock=IsUpdatedStock, @SalespersonReference2 = Reference2, @SalesPersonType=SalesPersonType, @SalesmanGroupID = GroupID ,@SalesmanCarID =ISNULL(CarID,0) 
	FROM SalesPersons WHERE CompanyID=@CompNo AND ID=@SalesmanNo
--goto EXITPRO


--if @ClientActive=27 and @CompNo=1 and (@PositionsID between 8000 and 8999 and @PositionsID not in (8202, 8021, 8024, 8303, 8533, 8536, 8537, 8542, 8820, 8621, 8121, 8721, 8722,8191))
--begin
--update CustomersFinancialDetails set PriceListID=323 where CompanyID=@CompNo and positionsid =@PositionsID and positionsid not in (8202, 8021, 8024, 8303, 8533, 8536, 8537, 8542, 8820, 8621, 8121, 8721, 8722,8191)
--End





If @clientactive=0 and @CompNo=2
Begin
Exec DemoSalesperson2
End


If @clientactive=117
Begin
--Select CURRENT_TIMESTAMP as time1
Create Table #historyitems (companyid1 int, positionid int , itemno1 Nvarchar(20))
insert into #historyitems
SELECT DISTINCT InvoiceHistoryDF.compno,@positionsid,InvoiceHistoryDF.ItemNo
FROM            InvoiceHistoryDF INNER JOIN
                         InvoiceHistoryHF ON InvoiceHistoryDF.CompNo = InvoiceHistoryHF.CompNo AND InvoiceHistoryDF.VouYear = InvoiceHistoryHF.VouYear AND InvoiceHistoryDF.VouNo = InvoiceHistoryHF.VouNo AND 
                         InvoiceHistoryDF.VouType = InvoiceHistoryHF.VouType
						 where salesmanno=@SalesmanNo

     insert into     SalesPersonItemsAssignment (CompanyID, PositionsID,ItemCode)
Select companyid1,positionid,itemno1 from #historyitems as S left outer join SalesPersonItemsAssignment as D on S.companyid1=D.CompanyID
and S.positionid=D.PositionsID and S.itemno1=D.ItemCode where S.companyid1=@CompNo and S.positionid=@PositionsID and D.ItemCode is NULL
Drop table #historyitems
--Select CURRENT_TIMESTAMP as time2
END
if @ClientActive = 124 or  @ClientActive = 150 or  @ClientActive = 155 or @ClientActive=213 or  @ClientActive = 170 Or ( @ClientActive = 147 and @CompNo=1)
BEGIN
	Update TransactionsHeaders 
	set PostedToERP = 1 
	where CompanyID = @CompNo AND ISNULL(PostedToERP,0) = 0



	Update TransfersOrdersHeaders 
	set PostedToERP = 1 
	where CompanyID = @CompNo AND ISNULL(PostedToERP,0) = 0



	Update SalesPersons 
	set IsUpdatedStock = 1 
	where CompanyID = @CompNo AND ID = @SalesmanNo
END

if @ClientActive = 52
Begin
Exec FixDuplicate_All @compno, @salesmanno
End

if @ClientActive=91
Exec FixCustomerMFDuplicateError3 @compno,@salesmanno

IF @ClientActive <> 27 --AND @ClientActive <> 30
BEGIN
	DELETE FROM OT_SendLog WHERE (CompanyID = @CompNo) AND (SalesmanNo = @SalesmanNo)
END

if @ClientActive=118 or @ClientActive =146 or @ClientActive =165
Begin
Exec FixCustomerMFDuplicateError @compno,@salesmanno
End
if @ClientActive=13
Begin
Exec FixDuplicate_All @compno,@salesmanno
END


INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES(@CompNo, @SalesmanNo, getDate(), 'Send Start')

DECLARE @BeginTime varchar(100)
DECLARE @EndTime varchar(100)

SET @BeginTime = Convert(varchar(20),GetDate(),108)

IF /*@ClientActive=30 or @ClientActive=29 or*/ @ClientActive=0 or @ClientActive=124 or ( @ClientActive=36 and @CompNo not in (4,2,7)) or @ClientActive =69 or @ClientActive =83 ----- ÒÚãØ
BEGIN
	update     OrdersHeaders   set PostedToERP =1
	WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo)  

	update     TransactionsHeaders   set PostedToERP =1
	WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) 
END

--IF @ClientActive=24 -----ÑíÊßæ 
--BEGIN

--update     TransactionsHeaders   set PostedToERP =1
--WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo)  and isnull (PostedToERP,0)=0 and CompanyID=1
--delete from [dbo].[SalesPersonItemsBalance] where   (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) 
--END 

SELECT      @IsMakeInvoiceAndOrder=SalesPersonsDevicePermissions.MakeSalesInvoice
FROM            SalesPersonsDevicePermissions INNER JOIN
                         SalesPersons ON SalesPersonsDevicePermissions.CompanyID = SalesPersons.CompanyID AND SalesPersonsDevicePermissions.PositionsID = SalesPersons.PositionID
WHERE        (SalesPersonsDevicePermissions.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo) AND (SalesPersonsDevicePermissions.MakeOrderTaking = 1) AND (SalesPersonsDevicePermissions.MakeSalesInvoice = 1)

IF @IsMakeInvoiceAndOrder =1 AND @ClientActive=85
BEGIN 
UPDATE       OrdersHeaders
SET                 PostedToERP = 1
WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND ISNULL(PostedToERP,0)=0 and DocumentsTypesID=3
END  

IF @ClientActive=73
BEGIN 

update TransactionsHeaders set TransactionsHeaders.PostedToERP=1
where CompanyID=@CompNo and SalesPersonID=@SalesmanNo

UPDATE       SalesPersons
SET               Reference2 = CompanyBranches.Name
FROM            SalesPersons INNER JOIN
                         CompanyBranches ON SalesPersons.CompanyID = CompanyBranches.CompanyID AND SalesPersons.CompanyBrancheID = CompanyBranches.ID
WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo)

END 

DECLARE @IsMakeInoice int 

SELECT        @IsMakeInoice = MakeSalesInvoice
FROM            SalesPersonsDevicePermissions
WHERE        (CompanyID = @CompNo) AND (MakeOrderTaking = 0) AND (MakeSalesInvoice = 1) AND (PositionsID = @PositionsID)

 
 if @ClientActive=77 -- Alyasmen Invoice not posted
 Begin

set  @Err =  'Alyasmen Invoice not posted'

--SELECT       distinct     StockNo, ID , CompanyID
--FROM            [YS-BONANZA01].CitMultiStore.dbo.InvInvoiceHeader_InCube AS ss INNER JOIN
--                         SalesPersons ON ss.StockNo = SalesPersons.Reference2
--WHERE        (SalesPersons.CompanyID = @CompNo ) AND (ID = @SalesmanNo)  AND  ISNULL (Sent,0)=0   
--IF @@ROWCOUNT>0 
--BEGIN 
--UPDATE SalesPersons SET IsUpdatedStock = 0
--		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 

--delete from OSFA_DB.dbo.OT_SalesmanMF where  (@CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) 
--select  @Err
--GoTO EXITPRO
--END 
END 



IF @ClientActive=63 -----Universal 
BEGIN

delete  from OSFA_DB.DBO.OT_StoreItemsQty_Main where CompNo=@CompNo and  SalesmanNo=@SalesmanNo  
INSERT INTO OSFA_DB.DBO.OT_StoreItemsQty_Main
                         (CompNo, SalesmanNo, StoreNo, ItemNo, Qty)

select distinct @CompNo,@SalesmanNo,999999,ModelNumber,sum (Balance) from StoreDataMain.dbo.Jard_View
group by ModelNumber ,StoreNumber
having StoreNumber = 1
END

Else IF @ClientActive=197  or @ClientActive=213 and @SalesmanNo not in(120,121,122,124,123)-----
BEGIN


exec Falcons_GetItemBalance @compno, 1



END




/*---/////Don not forget to uncommit for use in yameen Server//////


if @ClientActive=77
begin

if year (@SendDate )=2024
begin
 
delete from [dbo].[SalesPersonItemsBalance] where   (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) 
INSERT INTO [dbo].[SalesPersonItemsBalance]
           ([CompanyID]
           ,[SalesPersonID]
           ,[ItemCode]
           ,[UnitCode]
           ,[ItemQuantity])
SELECT        @CompNo AS Expr1, @SalesmanNo AS Expr2, WHStock_V.ItemNo, 1 Unit, WHStock_V.Quantity
FROM            SalesPersons INNER JOIN
                         [YS-BONANZA01].[CitMultiStoreLobik2024].dbo.WHStock_V  AS WHStock_V  ON
						 SalesPersons.Reference2 = WHStock_V.StoreNo and SalesPersons.CompanyID=@CompNo  INNER JOIN
                         Items ON WHStock_V.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS = Items.ItemCode
						 and Items.CompanyID=@CompNo
WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo)
end

else 
begin
delete from [dbo].[SalesPersonItemsBalance] where   (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) 
INSERT INTO [dbo].[SalesPersonItemsBalance]
           ([CompanyID]
           ,[SalesPersonID]
           ,[ItemCode]
           ,[UnitCode]
           ,[ItemQuantity])
SELECT        @CompNo AS Expr1, @SalesmanNo AS Expr2, WHStock_V.ItemNo, 1 Unit, WHStock_V.Quantity
FROM            SalesPersons INNER JOIN
                         [YS-BONANZA01].CitMultiStoreLobik.dbo.WHStock_V  AS WHStock_V  ON SalesPersons.CompanyID=@CompNo and 
						 SalesPersons.Reference2 = WHStock_V.StoreNo INNER JOIN
                         Items ON WHStock_V.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS = Items.ItemCode and 
						 Items.CompanyID=@CompNo  
WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo)

end
end

*/

if @ClientActive=128
Begin

Delete from OSFA_DB.dbo.OT_StoreItemsQty_Main where CompNo=@CompNo and SalesmanNo=@SalesmanNo
INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty_Main
                        (CompNo, SalesmanNo, ItemNo, Qty, StoreNo)
SELECT       distinct  StoresBalances.CompanyID, @SalesmanNo AS Expr1, OSFA_DB.dbo.OT_ItemsMF.ItemNo,   SUM (  StoresBalances.Qty ) AS Expr2, 999999 AS Expr3
FROM            StoresBalances INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON StoresBalances.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND OSFA_DB.dbo.OT_ItemsMF.SalesmanNo =@SalesmanNo AND 
                         StoresBalances.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
WHERE        (StoresBalances.CompanyID = @CompNo) and StoresBalances.StoreNo in (11)

group by OSFA_DB.dbo.OT_ItemsMF.ItemNo ,StoresBalances.CompanyID

END


IF @ClientActive=197 or @ClientActive=213
BEGIN

delete  from OSFA_DB.DBO.OT_StoreItemsQty_Main where CompNo=@CompNo and  SalesmanNo=@SalesmanNo  
INSERT INTO OSFA_DB.DBO.OT_StoreItemsQty_Main
                         (CompNo, SalesmanNo, StoreNo, ItemNo, Qty)

Select distinct @CompNo,@SalesmanNo,999999,itemcode , CASE WHEN ISNULL(ItemQuantity, 0)>0 THEN 1 ELSE 0 END   from SalesPersonItemsBalance
where  CompanyID=@CompNo and SalesPersonID=1  and ItemQuantity>0      



END
--IF @ClientActive=24 -----ÑíÊßæ 
--BEGIN

----update     TransactionsHeaders   set PostedToERP =1
----WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) 
--delete from [dbo].[SalesPersonItemsBalance] where   (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) 
--INSERT INTO [dbo].[SalesPersonItemsBalance]
--           ([CompanyID]
--           ,[SalesPersonID]
--           ,[ItemCode]
--           ,[UnitCode]
--           ,[ItemQuantity])
--SELECT        @CompNo AS Expr1, @SalesmanNo AS Expr2, CitMultiStore.dbo.WHStock_V.ItemNo, CitMultiStore.dbo.WHStock_V.Unit, CitMultiStore.dbo.WHStock_V.Quantity
--FROM            SalesPersons INNER JOIN
--                         CitMultiStore.dbo.WHStock_V ON SalesPersons.Reference2 = CitMultiStore.dbo.WHStock_V.StoreNo
--						 where (CompanyID = @CompNo) AND (ID = @SalesmanNo) 
--END
IF @ClientActive=68 -----ÇáÏåáßí 
Begin
if year(Getdate())=2023
Begin
delete from [dbo].[SalesPersonItemsBalance] where   (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) 
INSERT INTO [dbo].[SalesPersonItemsBalance]
           ([CompanyID]
           ,[SalesPersonID]
           ,[ItemCode]
           ,[UnitCode]
           ,[ItemQuantity])
SELECT        @CompNo AS Expr1, @SalesmanNo AS Expr2, CitMultiStore2023.dbo.WHStock_V.ItemNo, CitMultiStore2023.dbo.WHStock_V.Unit, CitMultiStore2023.dbo.WHStock_V.Quantity
FROM            SalesPersons INNER JOIN
                         CitMultiStore2023.dbo.WHStock_V ON SalesPersons.Reference2 = CitMultiStore2023.dbo.WHStock_V.StoreNo INNER JOIN
                         Items ON CitMultiStore2023.dbo.WHStock_V.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS = Items.ItemCode
WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo)
End
Else
Begin
--here
delete from [dbo].[SalesPersonItemsBalance] where   (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) 
INSERT INTO [dbo].[SalesPersonItemsBalance]
           ([CompanyID]
           ,[SalesPersonID]
           ,[ItemCode]
           ,[UnitCode]
           ,[ItemQuantity])
SELECT        @CompNo AS Expr1, @SalesmanNo AS Expr2, CitMultiStore.dbo.WHStock_V.ItemNo, CitMultiStore.dbo.WHStock_V.Unit, CitMultiStore.dbo.WHStock_V.Quantity
FROM            SalesPersons INNER JOIN
                         CitMultiStore.dbo.WHStock_V ON SalesPersons.Reference2 = CitMultiStore.dbo.WHStock_V.StoreNo INNER JOIN
                         Items ON CitMultiStore.dbo.WHStock_V.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS = Items.ItemCode
WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo) 
   

END
END

IF @ClientActive=121 
BEGIN

delete from [dbo].[SalesPersonItemsBalance] where   (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) 
INSERT INTO [dbo].[SalesPersonItemsBalance]
           ([CompanyID]
           ,[SalesPersonID]
           ,[ItemCode]
           ,[UnitCode]
           ,[ItemQuantity])
SELECT        @CompNo AS Expr1, @SalesmanNo AS Expr2, CitMultiStore.dbo.WHStock_V.ItemNo, CitMultiStore.dbo.WHStock_V.Unit,
 Round(CitMultiStore.dbo.WHStock_V.Quantity,2)
FROM            SalesPersons INNER JOIN
                         CitMultiStore.dbo.WHStock_V ON SalesPersons.Reference2 = CitMultiStore.dbo.WHStock_V.StoreNo INNER JOIN
                         Items ON CitMultiStore.dbo.WHStock_V.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS = Items.ItemCode
WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo) and  Round(CitMultiStore.dbo.WHStock_V.Quantity,2)>0
END

/*
if @ClientActive=77

begin

delete from [dbo].[SalesPersonItemsBalance] where   (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) 
INSERT INTO [dbo].[SalesPersonItemsBalance]
           ([CompanyID]
           ,[SalesPersonID]
           ,[ItemCode]
           ,[UnitCode]
           ,[ItemQuantity])
SELECT        @CompNo AS Expr1, @SalesmanNo AS Expr2, WHStock_V.ItemNo, WHStock_V.Unit, WHStock_V.Quantity
FROM            SalesPersons INNER JOIN
                         [YS-BONANZA01].CitMultiStore.dbo.WHStock_V  AS WHStock_V  ON SalesPersons.Reference2 = WHStock_V.StoreNo INNER JOIN
                         Items ON WHStock_V.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS = Items.ItemCode
WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo)

end
*/


 IF @ClientActive = 90 

BEGIN

if @CompNo in (1,3)
Begin
select 'ATYYYYYYYY'
DElete From SalesPersonItemsBalance WHERE (CompanyID = @CompNo) AND ( SalesPersonID = @SalesmanNo)    

INSERT INTO SalesPersonItemsBalance
                         (CompanyID, SalesPersonID, ItemCode, UnitCode, ItemQuantity)


SELECT        SalesPersons.CompanyID, SalesPersons.ID, Items.ItemCode, Items.UnitID, Chips_Integration.dbo.ItemsStockBalance.Qty
FROM            Chips_Integration.dbo.ItemsStockBalance INNER JOIN
                         SalesPersons ON CAST(Chips_Integration.dbo.ItemsStockBalance.StoreID AS nvarchar(100)) = SalesPersons.VehicleId INNER JOIN
                         Items ON SalesPersons.CompanyID = Items.CompanyID AND CAST(Chips_Integration.dbo.ItemsStockBalance.ItemNo AS nvarchar(100)) = Items.Reference2
			WHERE        (SalesPersons.CompanyID = @CompNo) AND ( SalesPersons.ID = @SalesmanNo)  

End
else
Begin


select 'ATYYYYYYYY'
DElete From SalesPersonItemsBalance WHERE (CompanyID = @CompNo) AND ( SalesPersonID = @SalesmanNo)    

INSERT INTO SalesPersonItemsBalance
                         (CompanyID, SalesPersonID, ItemCode, UnitCode, ItemQuantity)


SELECT        SalesPersons.CompanyID, SalesPersons.ID, Items.ItemCode, Items.UnitID, Nuts_Integration.dbo.ItemsStockBalance.Qty
FROM            Nuts_Integration.dbo.ItemsStockBalance INNER JOIN
                         SalesPersons ON CAST(Nuts_Integration.dbo.ItemsStockBalance.StoreID AS nvarchar(100)) = SalesPersons.VehicleId INNER JOIN
                         Items ON SalesPersons.CompanyID = Items.CompanyID AND CAST(Nuts_Integration.dbo.ItemsStockBalance.ItemNo AS nvarchar(100)) = Items.Reference2
			WHERE        (SalesPersons.CompanyID = @CompNo) AND ( SalesPersons.ID = @SalesmanNo)  

End
END 



IF @ClientActive =30 OR @ClientActive =78
Begin 

UPDATE       Items
SET                IsSuspended =1
FROM            (SELECT        CompNo, ItemNo, SUM(QtyOH) AS QTYOH
                          FROM            DB.dbo.InvBatchsMF
                          WHERE        (CompNo = @compno)
                          GROUP BY CompNo, ItemNo) AS Ata INNER JOIN
                         Items ON Ata.CompNo = Items.CompanyID AND Ata.ItemNo = Items.ItemCode
WHERE        (Ata.QTYOH <= 0) and Items.companyid=@compno
END


Declare @CheckPosted Varchar(100) = dbo.Fun_CheckSalesmanTransIsPosted(@CompNo, @SalesmanNo)
IF @CheckPosted <> ''
BEGIN
	INSERT INTO OSFA_DB.dbo.OT_ErrorLog (CompNo, SalesmanNo, ErrDesc, SysDate)
	VALUES        (@CompNo,@SalesmanNo,@CheckPosted,GetDate())
	print 'Data Not posted in OSFA:' + @CheckPosted
	goto EXITPRO
END

--IF @ClientActive=30
--BEGIN
--	SELECT      top 1 SalesPersonID
--	FROM            TransactionsHeaders
--	WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (ISNULL(PostedToERP, 0) = 0) 
--	IF @@ROWCOUNT = 0
--	BEGIN
--		UPDATE SalesPersons SET IsUpdatedStock = 1
--		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo)
--	END
--END 


IF @ClientActive=118 --and @SalesmanNo in (116,100,93)
BEGIN
	SELECT      top 1 SalesPersonID
	FROM            TransactionsHeaders
	WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (ISNULL(PostedToERP, 0) = 0) 
	IF @@ROWCOUNT = 1
	BEGIN
	
	DELETE FROM [OSFA_DB].[dbo].[OT_SalesmanMF] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
		UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo)
	END
	else
	Begin
	UPDATE SalesPersons SET IsUpdatedStock = 1
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo)
	End
END 

IF @ClientActive=13 
BEGIN
	SELECT      top 1 SalesPersonID
	FROM            TransactionsHeaders
	WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (ISNULL(PostedToERP, 0) = 0) 
	IF @@ROWCOUNT = 1
	BEGIN
	
	DELETE FROM [OSFA_DB].[dbo].[OT_SalesmanMF] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
		UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo)
		set @IsUpdatedStock=0
	END
	else
	Begin
	UPDATE SalesPersons SET IsUpdatedStock = 1
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo)
		set @IsUpdatedStock =1
	End
END 


IF @ClientActive=14
BEGIN
SELECT      top 1 SalesPersonID
	FROM            Receipts
	WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (ISNULL(PostedToERP, 0) = 0) AND (ISNULL(Receipts.Collected, 0) = 0) 
	IF @@ROWCOUNT = 0
	BEGIN
		UPDATE SalesPersons SET IsUpdatedStock = 1
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 
	END
	ELSE
	BEGIN
		UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 
	END
END



IF @ClientActive = 17 --Wadi 
BEGIN
	select distinct SLPRSNID from wadi.dbo.DI_SOPHEADR where POSTGSTS=0 AND SLPRSNID =(SELECT Reference1 FROM SalesPersons WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) ) COLLATE SQL_Latin1_General_CP1256_CI_AS 
	IF @@ROWCOUNT <> 0
	BEGIN
		UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 
		goto EXITPRO	
	END
End


IF @ClientActive = 17 --Wadi 
BEGIN

SELECT distinct  ID
FROM     WADI.dbo.DI_IVTRNDTL INNER JOIN
                  WADI.dbo.DI_IVTRNHDR ON WADI.dbo.DI_IVTRNDTL.IVDOCNBR = WADI.dbo.DI_IVTRNHDR.IVDOCNBR INNER JOIN
                  SalesPersons ON WADI.dbo.DI_IVTRNDTL.TRXLOCTN COLLATE SQL_Latin1_General_CP1256_CI_AS = SalesPersons.Reference1
where 	  wadi.dbo.DI_IVTRNHDR.POSTGSTS =0 and  (SalesPersons.CompanyID = @CompNo) AND (ID = @SalesmanNo) 
IF @@RowCount  >0
BEGIN 

UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 
		select 'Unload Order not posted '
		goto EXITPRO	

ENd 
	
END

IF @ClientActive = 17 --Wadi 
BEGIN

SELECT distinct  ID
FROM     WADI.dbo.DI_IVTRNDTL INNER JOIN
                  WADI.dbo.DI_IVTRNHDR ON WADI.dbo.DI_IVTRNDTL.IVDOCNBR = WADI.dbo.DI_IVTRNHDR.IVDOCNBR INNER JOIN
                  SalesPersons ON WADI.dbo.DI_IVTRNDTL.TRNSTLOC COLLATE SQL_Latin1_General_CP1256_CI_AS = SalesPersons.Reference1
			where 	  wadi.dbo.DI_IVTRNHDR.POSTGSTS =0 and  (SalesPersons.CompanyID = @CompNo) AND (ID = @SalesmanNo) 
IF @@RowCount  >0
BEGIN 

UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 
		select 'Upload Order not posted '
		goto EXITPRO	

END  
END
	
		if @ClientActive = 72
	BEGIN

		SELECT     CompNo
		FROM         Alpha_Integration.dbo.OT_InvoiceHF
		WHERE     (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (isNull(IsPosted,0) = 0) 
		IF @@ROWCOUNT > 0
		BEGIN
			print 'retaj Inoice validation'
			UPDATE SalesPersons SET IsUpdatedStock = 0
			WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 

			delete from OSFA_DB.dbo.OT_SalesmanMF where  (@CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) 

			goto EXITPRO
		END
	END 



	if @ClientActive = 41
	BEGIN

		SELECT     CompNo
		FROM         Alpha_Integration.dbo.OT_InvoiceHF
		WHERE     (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (isNull(IsPosted,0) = 0) 
		IF @@ROWCOUNT > 0
		BEGIN
			print 'Attieh Inoice validation'

			UPDATE SalesPersons SET IsUpdatedStock = 0
			WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 

			delete from OSFA_DB.dbo.OT_SalesmanMF where  (@CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) 

			goto EXITPRO
		END


		
	     SELECT     CompanyID
	     FROM         TransactionsHeaders
	     WHERE     (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (isNull(PostedToERP,0) = 0) 
		 	IF @@ROWCOUNT > 0
		BEGIN
			print 'Attieh Invoice validation'

			UPDATE SalesPersons SET IsUpdatedStock = 0
			WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 

			delete from OSFA_DB.dbo.OT_SalesmanMF where  (@CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) 

			goto EXITPRO
		END


		 SELECT     CompNo
	     FROM         OSFA_DB..OT_InvoiceHF
	     WHERE     (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (isNull(IsPosted,0) = 0) 
		 IF @@ROWCOUNT > 0
		BEGIN
			print 'Attieh Invoice validation'

			UPDATE SalesPersons SET IsUpdatedStock = 0
			WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 

			delete from OSFA_DB.dbo.OT_SalesmanMF where  (@CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) 

			goto EXITPRO
		END


	END 

	IF  @ClientActive <> 35 
	Begin
	if @ClientActive=122
	    Begin
	        SELECT      top 1 SalesPersonID
			FROM            TransactionsHeaders
			WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (ISNULL(PostedToERP, 0) = 0) AND (ISNULL(IsVoid, 0) = 0) AND (ISNULL(Approve, 0) = 1)
			and CreditCash=1
			IF @@ROWCOUNT = 0
			BEGIN
				UPDATE SalesPersons SET IsUpdatedStock = 1
				WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 
				Set @IsUpdatedStock =1
				End
	     end
		 else IF @ClientActive <> 11   --and  @ClientActive <> 30
		BEGIN
			SELECT      top 1 SalesPersonID
			FROM            TransactionsHeaders
			WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (ISNULL(PostedToERP, 0) = 0) AND (ISNULL(IsVoid, 0) = 0) AND (ISNULL(Approve, 0) = 1)
			IF @@ROWCOUNT = 0
			BEGIN
				UPDATE SalesPersons SET IsUpdatedStock = 1
				WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 
				Set @IsUpdatedStock =1
			END
			ELSE
			BEGIN
				UPDATE SalesPersons SET IsUpdatedStock = 0
				WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 
			END
		END
	END 



IF @ClientActive = 51 or @ClientActive=136  or @ClientActive=5
BEGIN
	SELECT      top 1 SalesPersonID
	FROM            TransactionsHeaders
	WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (ISNULL(PostedToERP, 0) = 0) AND (ISNULL(IsVoid, 0) = 0) AND (ISNULL(Approve, 1) = 1)
	IF @@ROWCOUNT = 0
	BEGIN
		UPDATE SalesPersons SET IsUpdatedStock = 1
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 
	END
	ELSE
	BEGIN
		UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo)
				print 'Sujab Validation'
			goto EXITPRO
	
	END
END


if @ClientActive = 14
begin
	declare @C int
	set @C = 0
	select @C = COUNT(*) from Yolande_Integ.dbo.InvoiceHF
	where (SalesmanNo = @SalesmanNo) and isnull(IsPosted,0) = 0
	if @C <> 0
	BEGIN
		UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo)
		print '2'
		goto EXITPRO
	END 
	
	set @C = 0
	select @C = COUNT(*) from Yolande_Integ.dbo.Payments
	where (SalesmanNo = @SalesmanNo) and isnull(IsPosted,0) = 0
	if @C <> 0
	BEGIN
		UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo)
		print '3'
		goto EXITPRO
	END 
	
	set @C = 0
	select  COUNT(*) from Yolande_Integ.dbo.ConsOrderHF
		where  (SalesmanNo = @SalesmanNo) and isnull(Posted,0) = 0
	if @C <> 0
	BEGIN
		UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo)
		print '4'
		goto EXITPRO
	END
end

--if @ClientActive = 5
--begin

--declare @Ref1 nvarchar (50)
--select @ref1 =Reference1 from salespersons  where  id =@SalesmanNo
--	declare @C1 int
--	set @C1 = 0
--	select @C1 = COUNT(*) from Alpha_Integration.dbo.OT_InvoiceHF
--	where compno = @CompNo and  (SalesmanNo = @ref1) and isnull(IsPosted,0) = 0
--	if @C1 <> 0
--	BEGIN
--		UPDATE SalesPersons SET IsUpdatedStock = 0
--		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo)
--		print '5'
--		goto EXITPRO
--	END 
	 
--end
--if @ClientActive = 14
--begin
--	declare @C int
--	set @C = 0
--	select @C = COUNT(*) from Alpha_Integration.dbo.OT_InvoiceHF
--	where compno = @CompNo and  (SalesmanNo = @SalesmanNo) and isnull(IsPosted,0) = 0
--	if @C <> 0
--	BEGIN
--		UPDATE SalesPersons SET IsUpdatedStock = 0
--		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo)
		
--		goto EXITPRO
--	END 
	
--	set @C = 0
--	select @C = COUNT(*) from Alpha_Integration.dbo.OT_Payments
--	where compno = @CompNo and  (SalesmanNo = @SalesmanNo) and isnull(IsPosted,0) = 0
--	if @C <> 0
--	BEGIN
--		UPDATE SalesPersons SET IsUpdatedStock = 0
--		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo)
		
--		goto EXITPRO
--	END 
	
--	set @C = 0
--	select  COUNT(*) from Alpha_Integration.dbo.OT_ConsOrderHF
--	where compno = @CompNo and  (SalesmanNo = @SalesmanNo) and isnull(Posted,0) = 0
--	if @C <> 0
--	BEGIN
--		UPDATE SalesPersons SET IsUpdatedStock = 0
--		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo)
		
--		goto EXITPRO
--	END
--end




if @ClientActive = 68 and @IsMakeOrderOnly=1

BEGIN

SELECT    distinct     CitMultiStore.dbo.InvInvoiceHeader_InCube.StockNo, ID , CompanyID
FROM            CitMultiStore.dbo.InvInvoiceHeader_InCube INNER JOIN
                         SalesPersons ON CitMultiStore.dbo.InvInvoiceHeader_InCube.StockNo = SalesPersons.Reference2
WHERE        (SalesPersons.CompanyID = @CompNo ) AND (ID = @SalesmanNo)  AND  ISNULL (Sent,0)=0   
IF @@ROWCOUNT>0 
BEGIN 


UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 

		delete from OSFA_DB.dbo.OT_SalesmanMF where  (@CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) 
END 
END 



if @ClientActive = 133

BEGIN
declare @RefId1 int
select @RefId1=Reference1 from SalesPersons where CompanyID=@CompNo and id=@SalesmanNo
select 'ssss'
	SELECT     VouYear
	FROM         Shams_Integration.dbo.InvoiceHF
	WHERE      (SalesmanNo = @RefId1) AND (isNull(IsPosted,0) = 0)   and Shams_Integration.dbo.InvoiceHF.VouType in (1,2)
	IF @@ROWCOUNT > 0
	BEGIN
	print 'Invoice and Return (Shams) not posted'
		UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 

		select * from OSFA_DB.dbo.OT_SalesmanMF where  (@CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) 

			goto EXITPRO
	END
End


if @ClientActive = 30   or @ClientActive = 84

BEGIN


	SELECT     CompNo
	FROM         Alpha_Integration.dbo.OT_InvoiceHF
	WHERE     (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (isNull(IsPosted,0) = 0) 
	IF @@ROWCOUNT > 0
	BEGIN
	print 'Zoumt Inoice validation'
		UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 

		delete from OSFA_DB.dbo.OT_SalesmanMF where  (@CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) 

			goto EXITPRO
	END

	SELECT     CompNo
	FROM         Alpha_Integration.dbo.OT_Payments
	WHERE     (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (isNull(IsPosted,0) = 0)
	IF @@ROWCOUNT > 0
	BEGIN
		print 'Zoumt payment validation'

		UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 

		delete from OSFA_DB.dbo.OT_SalesmanMF where  (@CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) 

		goto EXITPRO
	END

	SELECT     CompNo
	FROM         Alpha_Integration.dbo.OT_ConsOrderHF
	WHERE     (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (isNull(IsTransfer,0) = 0) and (OrderType =2) 
	IF @@ROWCOUNT > 0
	BEGIN
	print 'Zoumt unload validation'
		UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 

		delete from OSFA_DB.dbo.OT_SalesmanMF where  (@CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) 


			goto EXITPRO
	END
END

if @ClientActive = 26
BEGIN
	SELECT     CompNo
	FROM         Alpha_Integration.dbo.OT_Payments
	WHERE     (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (isNull(IsPosted,0) = 0)
	IF @@ROWCOUNT > 0
	BEGIN
		UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 
	END
END

if  @ClientActive = 16 
begin
	SELECT     CompanyID
	FROM         TransactionsHeaders
	WHERE     (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (isNull(PostedToERP,0) = 0) 
	IF @@ROWCOUNT > 0
	BEGIN	
		UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 

		delete from OSFA_DB.dbo.OT_SalesmanMF where  (@CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) 

		goto EXITPRO
	END

	SELECT     CompanyID
	FROM         Receipts
	WHERE     (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (isNull(PostedToERP,0) = 0)  
	IF @@ROWCOUNT > 0
	BEGIN	
		UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 

		delete from OSFA_DB.dbo.OT_SalesmanMF where  (@CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) 

		goto EXITPRO
	END

	SELECT     CompNo
	FROM         Alpha_Integration.dbo.OT_InvoiceHF
	WHERE     (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (isNull(IsPosted,0) = 0) 
	IF @@ROWCOUNT > 0
	BEGIN	
		UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 

		delete from OSFA_DB.dbo.OT_SalesmanMF where  (@CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) 

		goto EXITPRO
	END

	SELECT     CompNo
	FROM         Alpha_Integration.dbo.OT_Payments
	WHERE     (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (isNull(IsPosted,0) = 0)
	IF @@ROWCOUNT > 0
	BEGIN	
		UPDATE SalesPersons SET IsUpdatedStock = 0
		WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo) 

		delete from OSFA_DB.dbo.OT_SalesmanMF where  (@CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) 

		goto EXITPRO
	END
end

SELECT @CalcItemBalance = ISNULL(CalcItemBalance,0), @SerialType = ISNULL(SerialType,0), @LockOnSendData = IsNUll(LockOnSendData,0), @UseRangePrice = UseRangePrice FROM CompanyParameters WHERE (CompanyID = @CompNo)
SELECT @SalesmanPromGroup = ID FROM SalesPersonsGroups WHERE CompanyID = @CompNo AND ISNULL(SalesPersonID, 0) = @SalesmanNo

Declare @GroupCustByRelatedSalespersons as int
Declare @GroupCustByRelatedSalespersons_0 as int

SELECT  @GroupCustByRelatedSalespersons = Op_Value FROM  OSFA_DB.dbo.OT_SystemOptions WHERE (CompNo = @CompNo) AND (Op_ID = 176) AND (SalesmanNo=@SalesmanNo)
SELECT  @GroupCustByRelatedSalespersons_0 = Op_Value FROM  OSFA_DB.dbo.OT_SystemOptions WHERE (CompNo = @CompNo) AND (Op_ID = 176) AND (SalesmanNo=0)

SET @GroupCustByRelatedSalespersons=ISNULL(@GroupCustByRelatedSalespersons,@GroupCustByRelatedSalespersons_0)

SELECT        @IsMakeOrder = MakeOrderTaking
FROM            SalesPersonsDevicePermissions
WHERE        (CompanyID = @CompNo) AND (MakeOrderTaking = 1) AND (MakeSalesInvoice = 0) AND (PositionsID = @PositionsID)

SELECT        @IsMakeOrderOnly = MakeOrderTaking
FROM            SalesPersonsDevicePermissions
WHERE        (CompanyID = @CompNo) AND (MakeOrderTaking = 1)  AND (PositionsID = @PositionsID)

SELECT        @IsMakeInvoice = MakeSalesInvoice
FROM         SalesPersonsDevicePermissions
WHERE        (CompanyID = @CompNo)   AND (PositionsID = @PositionsID)


SET @UseRangePrice =  ISNULL(@UseRangePrice,0)
SET @PositionsID=ISNULL(@PositionsID,0)
SET @ClientActive=ISNULL(@ClientActive,0)
SET @IsUpdatedStock=ISNULL(@IsUpdatedStock,1)
SET @CalcItemBalance = ISNULL(@CalcItemBalance,0)
SET @SerialType = ISNULL(@SerialType,0)
SET @LockOnSendData = ISNULL(@LockOnSendData,0)

IF @LockOnSendData = 1
BEGIN
	UPDATE       SalesPersons
	SET                IsSendData = 1
	WHERE        (CompanyID = @CompNo) AND (ID = @SalesmanNo)
END

IF   @ClientActive=35 Or @ClientActive=88 OR @ClientActive=80 OR @ClientActive=131 OR (@ClientActive = 42 AND @CompNo = 1 and @SalesmanNo in (133,134,135))--and @SalesmanNo=28 OR @SalesmanNo=31   
Begin 
set  @IsUpdatedStock=1
end 

IF @IsUpdatedStock=0 
BEGIN
	print 'IsUpdatedStock = False'
	goto EXITPRO
END 

IF @ClientActive=27
BEGIN

SELECT       @AllowReplacement = SalesPersonsDevicePermissions.AllowItemsReplacement
FROM            SalesPersonsDevicePermissions INNER JOIN
                         SalesPersons ON SalesPersonsDevicePermissions.CompanyID = SalesPersons.CompanyID AND SalesPersonsDevicePermissions.PositionsID = SalesPersons.PositionID
WHERE        (SalesPersonsDevicePermissions.CompanyID = @CompNo) and ID= @SalesmanNo 

IF @AllowReplacement =1
Begin 

select * from  osfa_db..OT_SystemOptions
where CompNo=@CompNo and SalesmanNo=@SalesmanNo and Op_ID in (266,276)
IF @@ROWCOUNT <> 2
BEGIN 
delete  from  osfa_db..OT_SystemOptions
where CompNo=@CompNo and SalesmanNo=@SalesmanNo and Op_ID in (266,276)

INSERT  INTO osfa_db..OT_SystemOptions
Values (@CompNo,266,@SalesmanNo,'Use Items Batches In Vouchers','4;12','0=Off | 1=Invoice | 2=Return | 7=UnLoad | 
4=Customer Stock  With ; Separated',NULL)

INSERT  INTO osfa_db..OT_SystemOptions
Values (@CompNo,276,@SalesmanNo,'Select Items Batches From List','1','0=Off | 1=On',NULL)
END 
END
END 

IF @ClientActive = 145
BEGIN
	declare @Op232 nvarchar(1) = CASE WHEN @SalesmanNo < 1000 THEN '1' ELSE '0' END

	delete  from  osfa_db..OT_SystemOptions
	where CompNo=@CompNo and SalesmanNo=@SalesmanNo and Op_ID = (232)

	INSERT INTO OSFA_DB.dbo.OT_SystemOptions
							 (CompNo, Op_ID, SalesmanNo, Op_Desc, Op_Value, Notes, PrinterType)
	VALUES        (@CompNo, 232,@SalesmanNo, 'Generate Auto Payment For Cash Invoices', @Op232, '0=Off | 1=On', NULL)
END

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Check Salesman Transactions [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

---Begin Send Company Data------------------------------------------------------------------------------

SET @BeginTime = Convert(varchar(20),GetDate(),108)

DELETE FROM [OSFA_DB].[dbo].[OT_PromotionsSalesmanGroupsLink] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_Banks] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_BanksAccounts] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_Branchs] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_BusinessUnitDef] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo

												 
															   
																																																					  

												   

if @ClientActive = 62 or  @ClientActive = 111 or @ClientActive=118 or @ClientActive =165
BEGIN
	DELETE FROM [OSFA_DB].[dbo].[OT_COMPANY] WHERE [SalesmanNo]=@SalesmanNo
END
ELSE
BEGIN
	DELETE FROM [OSFA_DB].[dbo].[OT_COMPANY] WHERE [comp_num]=@CompNo AND [SalesmanNo]=@SalesmanNo
END


DELETE FROM [OSFA_DB].[dbo].[OT_CustType] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_CustomersClasses] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo

DELETE FROM [OSFA_DB].[dbo].[OT_DocTypes] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_GeoLevel1] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo

												 
															   
																																																  

												   
DELETE FROM [OSFA_DB].[dbo].[OT_ItemsCateg] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_ItemsSubCateg] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_PromotionsHeaders] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_PromotionsCondUnCodInput] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_PromotionsCondUnCodOutput] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo

												 
															   
																																																										   

												   

DELETE FROM [OSFA_DB].[dbo].[OT_PromotionsRangeInputOutput] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_PromotionsSalesmanGroupsLink] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_PromotionsCustomersGroupsLink] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_RouteMF] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_ItemUnits] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo

												 
															   
																																																													 

												   

DELETE FROM [OSFA_DB].[dbo].[OT_PaymentsTypes] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_PriceListsMF] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_Surveys] WHERE [CompNo] =@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_Surveys_Questions] WHERE [CompNo] =@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_Surveys_Questions_Options] WHERE [CompNo] =@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_CompanyBranches] WHERE [CompNo] =@CompNo AND [SalesmanNo]=@SalesmanNo

												 
															   
																																																												 

												   

DELETE FROM [OSFA_DB].[dbo].[OT_Reasons] WHERE [CompNo] = @CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_ReprintReasons] WHERE [CompNo] = @CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_Currency] WHERE [CompNo] = @CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].OT_CustomersGroups WHERE [CompNo] = @CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_CustomersGPSLocations] WHERE CompanyID = @CompNo AND [SalesmanNo]=@SalesmanNo

												 
															   
																																																				 
---End Send Company Data------------------------------------------------------------------------------

												   

DELETE FROM [OSFA_DB].[dbo].[OT_ItemsMF] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_CustomerMF] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_PriceList] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_ItemsQtyAvg] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo

												 
															   
																																												 

												   

DELETE FROM [OSFA_DB].[dbo].[OT_SalesmanRoute] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo

if @ClientActive <> 177
BEGIN
	DELETE FROM [OSFA_DB].[dbo].[OT_StoreItemsQty] WHERE [CompNo]=@CompNo AND [StoreNo]=@SalesmanNo
END

IF @ClientActive<>6
begin 
DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE [CompNo]=@CompNo AND SalesmanNo=@SalesmanNo
end 
DELETE FROM [OSFA_DB].[dbo].[OT_PromotionsGroupsCustomersLink] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo

												 
															   
																																																		 

												   

DELETE FROM [OSFA_DB].[dbo].[OT_StateAccBalance] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_Drawers] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_CreditInvoiceList] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_CustStockHistory] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo

												 
															   
																																																   

												   

DELETE FROM [OSFA_DB].[dbo].[OT_SystemOptions] WHERE [CompNo]=@CompNo AND [SalesmanNo]=@SalesmanNo AND Op_ID in(1,31,32,33,34,39)
DELETE FROM [OSFA_DB].[dbo].[OT_CustomerSalesByCategory] WHERE [CompNo]=@CompNo
DELETE FROM [OSFA_DB].[dbo].[OT_CompetitiveItems] WHERE [CompanyID] = @CompNo AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_CustomerChqList] WHERE [CompNo] = @CompNo  AND [SalesmanNo]=@SalesmanNo
DELETE FROM [OSFA_DB].[dbo].[OT_SalesmanNotebookSerials] WHERE(CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)

												 
															   
																																																											

												   

DELETE FROM [OSFA_DB].[dbo].[OT_SalesmanItemBonusTarget] WHERE(CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
DELETE FROM [OSFA_DB].[dbo].[OT_InvoiceReturnLinkToTab] WHERE(CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
DELETE FROM [OSFA_DB].[dbo].[OT_Contracts] WHERE [CompNo] = @CompNo AND (SalesmanNo = @SalesmanNo)
DELETE FROM [OSFA_DB].[dbo].[OT_ContractItems] WHERE [CompNo] = @CompNo AND (SalesmanNo = @SalesmanNo)
DELETE FROM [OSFA_DB].[dbo].[OT_CouponsInfo] WHERE [CompNo] = @CompNo AND (SalesmanNo = @SalesmanNo)

												 
															   
																																																								

												   

DELETE FROM [OSFA_DB].[dbo].[OT_SalesmanProcedures]  WHERE [CompNo] = @CompNo AND (SalesmanNo = @SalesmanNo)
DELETE from [OSFA_DB].[dbo].[OT_ProspectiveCustomer]  WHERE [CompNo] = @CompNo AND (SalesmanNo = @SalesmanNo)

if @ClientActive = 27
begin
DELETE from [OSFA_DB].[dbo].OT_LinkedSalesman  WHERE [CompNo] = @CompNo   and Ref1 not in ('100','101','105')
end
else
begin
DELETE from [OSFA_DB].[dbo].OT_LinkedSalesman  WHERE [CompNo] = @CompNo AND (SalesmanNo = @SalesmanNo)
end

DELETE from [OSFA_DB].[dbo].OT_ItemsPriceExceptions  WHERE [CompNo] = @CompNo AND (SalesmanNo = @SalesmanNo)
DELETE from [OSFA_DB].[dbo].OT_SalesmanTransactionsSerialsMulti  WHERE [CompNo] = @CompNo AND (SalesmanNo = @SalesmanNo)
DELETE from [OSFA_DB].[dbo].OT_ItemsPriority  WHERE CompanyID = @CompNo AND (SalesmanNo = @SalesmanNo)

												 
															   
																																																																	

												   

DELETE from [OSFA_DB].[dbo].OT_ImageTypes  WHERE [CompNo] = @CompNo AND (SalesmanNo = @SalesmanNo)
DELETE from [OSFA_DB].[dbo].OT_CustomersItemsAssigment  WHERE [CompanyID] = @CompNo AND (SalesmanNo = @SalesmanNo)
DELETE from [OSFA_DB].[dbo].OT_ItemsUnitsBarcode  WHERE [CompNo] = @CompNo AND (SalesmanNo = @SalesmanNo)
DELETE from [OSFA_DB].[dbo].OT_BatchsInfo WHERE [CompNo] = @CompNo AND (SalesmanNo = @SalesmanNo)
DELETE from [OSFA_DB].[dbo].OT_CustIssueAmount WHERE [CompNo] = @CompNo AND (SalesmanNo = @SalesmanNo)

												 
															   
																																																				   

												   

DELETE from [OSFA_DB].[dbo].OT_ReturnChecks WHERE [CompNo] = @CompNo AND (SalesmanNo = @SalesmanNo)
DELETE from [OSFA_DB].[dbo].OT_ReceiptRequests WHERE CompanyID = @CompNo AND (SalesmanNo = @SalesmanNo)
DELETE from [OSFA_DB].[dbo].OT_ReceiptRequestsInvoicesLink WHERE CompanyID = @CompNo AND (SalesmanNo = @SalesmanNo)
DELETE from [OSFA_DB].[dbo].[OT_ItemsSalesUnits] WHERE CompanyID = @CompNo AND (SalesmanNo = @SalesmanNo)

SET @EndTime = Convert(varchar(20),GetDate(),108)

INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Clear Data [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

print 'begin send'


if @ClientActive =21 and @CompNo = 1
BEGIN

DELETE FROM SalesPersonItemsBalance
WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo)

INSERT INTO SalesPersonItemsBalance (CompanyID, SalesPersonID, ItemCode, ItemQuantity, UnitCode)
SELECT        Companies.ID, @SalesmanNo AS Expr1, Items.ItemCode, ViTechIntegration.dbo.IVVwItemBalances.balance_qty, ItemsUnits.ID
FROM            ViTechIntegration.dbo.IVVwItemBalances INNER JOIN
                         Companies ON ViTechIntegration.dbo.IVVwItemBalances.company_code = Companies.Reference1 COLLATE Arabic_CI_AI INNER JOIN
                         SalesPersonItemsAssignment ON Companies.ID = SalesPersonItemsAssignment.CompanyID AND 
                         ViTechIntegration.dbo.IVVwItemBalances.item_code1 COLLATE SQL_Latin1_General_CP1256_CI_AS = SalesPersonItemsAssignment.ItemCode INNER JOIN
                         Items ON SalesPersonItemsAssignment.CompanyID = Items.CompanyID AND SalesPersonItemsAssignment.ItemCode = Items.ItemCode INNER JOIN
                         ItemsUnits ON Items.CompanyID = ItemsUnits.CompanyID AND Items.UnitID = ItemsUnits.ID
WHERE        (ViTechIntegration.dbo.IVVwItemBalances.balance_qty <> 0) AND (ViTechIntegration.dbo.IVVwItemBalances.siteid = @SalespersonReference2) AND 
                         (Companies.ID = @CompNo) AND (SalesPersonItemsAssignment.PositionsID = @PositionsID)
END
Else
BEGIN

Print 'Send Karasheh Balance'		
select 0
--EXEC SAP_GetItemBalance_Karadsheh @CompNo,@SalesmanNo
END


if @ClientActive = 39 or @ClientActive=64
BEGIN
	Declare @ErrorInStock int
	SET @ErrorInStock = 0
	EXEC dbo.IscoJordan_Integ_GetItemsBalance @CompNo, @SalesmanNo,@PositionsID,@ErrorInStock output 
	IF @ErrorInStock <> 0
	BEGIN
		delete from OSFA_DB.dbo.OT_SalesmanMF WHERE CompNo = @CompNo And SalesmanNo = @SalesmanNo
		print '7'
		goto EXITPRO
	END
END




--IF @ClientActive = 6
--Begin 

--EXEC [GP_Integ_GetItemBalanceFromView] @CompNo,@SalesmanNo

--UPDATE       SalesPersons
--SET                IsUpdatedStock = 1
--FROM            SalesPersons INNER JOIN
--                         GP_Integration.dbo.SalesTeamStoreLink ON SalesPersons.Reference1 = GP_Integration.dbo.SalesTeamStoreLink.SalesPersonID INNER JOIN
--                         GP_Integration.dbo.ItemsBalance ON GP_Integration.dbo.SalesTeamStoreLink.StoreID = GP_Integration.dbo.ItemsBalance.StoreID
--WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo)



--UPDATE       SalesPersons
--SET                IsUpdatedStock = 1
--FROM            SalesPersons INNER JOIN
--                         SalesPersonsDevicePermissions ON SalesPersons.CompanyID = SalesPersonsDevicePermissions.CompanyID AND SalesPersons.PositionID = SalesPersonsDevicePermissions.PositionsID
--WHERE        (SalesPersons.ID = @SalesmanNo) AND (SalesPersons.CompanyID = @CompNo) AND (SalesPersonsDevicePermissions.MakeOrderTaking = 1)


--END


--if @ClientActive = 9
--begin
--	declare @FindSalesman int
--	SELECT    @FindSalesman = Count(*)
--	FROM         SalesPersonDeleteBalance
--	WHERE     (Compno = @CompNo) AND (SalesmanNo = @SalesmanNo)
--	if @FindSalesman = 0
--	begin			
--		DELETE FROM SalesPersonItemsBalance
--		WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo)
--	end

--	DELETE
--	FROM         SalesPersonDeleteBalance
--	WHERE     (Compno = @CompNo) AND (SalesmanNo = @SalesmanNo)
--end

Declare @OnlyCustomersOnRoutes as bit
--SELECT        @OnlyCustomersOnRoutes = Op_Value
--FROM            OSFA_DB.dbo.OT_SystemOptions
--WHERE        (CompNo = @CompNo) AND (Op_ID = 28)

SET @OnlyCustomersOnRoutes = [dbo].[Fun_GetSalesmanSysOpValue] (@CompNo,@SalesmanNo,28)


Declare @SupervisorNo nvarchar(50)
Declare @SupervisorName nvarchar(100)
Declare @SupervisorTel nvarchar(50)
print 'brqa'
SELECT     @SupervisorNo = Parent
FROM         SalesPersons
WHERE     (CompanyID = @CompNo) AND (ID = @SalesmanNo)

SELECT @SupervisorName = Name, @SupervisorTel = TelephoneNo 
FROM		SalesPersons
WHERE     (CompanyID = @CompNo) AND (ID = @SupervisorNo)

select salesman from GetSalesman() where company =@CompNo and TType ='FOC' AND salesman = @SalesmanNo
if @@rowCount <> 0
begin
	print '8'
	goto EXITPRO
end

SET @BeginTime = Convert(varchar(20),GetDate(),108)

---Begin Send Company Data------------------------------------------------------------------------------
SELECT        CompanyID
FROM            OSFA_DB.dbo.CompanyParameters
WHERE        (CompanyID = @CompNo)
IF @@ROWCOUNT = 0
BEGIN
	INSERT INTO OSFA_DB.dbo.CompanyParameters (CompanyID, ImportTransInServerDate, NumberSavedFraction, TruncRoundValue)
	SELECT        CompanyID, 0, NumberSavedFraction, TruncRoundValue
	FROM            CompanyParameters
	WHERE        (CompanyID = @CompNo)
END
ELSE
BEGIN
	UPDATE       OSFA_DB.dbo.CompanyParameters
	SET                NumberSavedFraction = CompanyParameters_1.NumberSavedFraction,
					   TruncRoundValue = CompanyParameters_1.TruncRoundValue
	FROM            OSFA_DB.dbo.CompanyParameters INNER JOIN
							 CompanyParameters AS CompanyParameters_1 ON OSFA_DB.dbo.CompanyParameters.CompanyID = CompanyParameters_1.CompanyID
	WHERE        (OSFA_DB.dbo.CompanyParameters.CompanyID = @CompNo)
END


	INSERT INTO OSFA_DB.dbo.OT_Currency
						  (CompNo, SalesmanNo, CurrID, CurrName, CurrName2, CurrRate, CurrFraction, Ref1, Ref2)
	SELECT				   @CompNo, @SalesmanNo, ID, Name, ShortName, Reference1, Fraction,'',''
	FROM         Currencies

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'CompanyParameters, OT_Currency [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')


IF @ClientActive = 5 OR @ClientActive = 0 OR @ClientActive = 19
BEGIN
	SELECT     @ItemCategLevel=  MAX(ItemsCategories.[Level])
	FROM         Items INNER JOIN
						  ItemsCategories ON Items.CompanyID = ItemsCategories.CompanyID AND Items.CategCode = ItemsCategories.CategCode
	WHERE     (Items.CompanyID = @CompNo)
END
ELSE IF @ClientActive = 15 OR @ClientActive = 85    
BEGIN
	SET @ItemCategLevel = 2
END
ELSE
BEGIN
	SELECT     @ItemCategLevel=  (ItemsCategories.[Level])
	FROM         Items INNER JOIN
						  ItemsCategories ON Items.CompanyID = ItemsCategories.CompanyID AND Items.CategCode = ItemsCategories.CategCode
	WHERE     (Items.CompanyID = @CompNo)
END

SET @BeginTime = Convert(varchar(20),GetDate(),108)

INSERT INTO [OSFA_DB].[dbo].[OT_Banks]
           ([CompNo]
		   ,[SalesmanNo]
           ,[BankNo]
           ,[ArDesc]
           ,[EngDesc])
SELECT     CompanyID, @SalesmanNo, ID, Name AS Ar, Reference2 AS En
FROM         Banks
WHERE     (CompanyID = @CompNo)


INSERT INTO [OSFA_DB].[dbo].[OT_BanksAccounts]
           ([CompNo]
           ,[SalesmanNo]
           ,[BankID]
           ,[ID]
           ,[AccountNumber]
           ,[Reference1]
           ,[Reference2])
SELECT     CompanyID, @SalesmanNo,[BankID], ID, [AccountNumber], Reference1, Reference2
FROM         BanksAccounts
WHERE     (CompanyID = @CompNo)


INSERT INTO [OSFA_DB].[dbo].[OT_Branchs]
           ([CompNo]
		   ,[SalesmanNo]
           ,[BankNo]
           ,[BranchNo]
           ,[ArDesc]
           ,[EngDesc])
SELECT     Branches.CompanyID, @SalesmanNo, Banks.ID, Branches.ID AS Branch, Branches.Name AS Ar, Branches.Name AS En
FROM         Banks INNER JOIN
                      Branches ON Banks.CompanyID = Branches.CompanyID AND Banks.ID = Branches.BankID
WHERE     (Branches.CompanyID = @CompNo) 


INSERT INTO [OSFA_DB].[dbo].[OT_BusinessUnitDef]
           ([CompNo]
		   ,[SalesmanNo]
           ,[BusUnitID]
           ,[BusUnitDescAr]
           ,[BusUnitDescEng])
SELECT     CompanyID, @SalesmanNo, ID, Name AS Ar, 
		(select Reference1 from BusinessUnits where ID = i.Parent and CompanyID = i.CompanyID)
FROM         BusinessUnits as i
WHERE     (CompanyID = @CompNo) 

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_Banks, OT_BanksAccounts, OT_Branchs, OT_BusinessUnitDef [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

SET @BeginTime = Convert(varchar(20),GetDate(),108)

IF @ClientActive = 62 -- ÇáäÇÚæÑí
BEGIN
	INSERT INTO OSFA_DB.dbo.OT_COMPANY
							 (comp_num, SalesmanNo, comp_name, comp_ename, comp_addr1, comp_eaddr1, comp_addr2, comp_eaddr2, comp_tel1, comp_tel2, comp_fax, comp_tlx, comp_logo, SalesTaxNo, NumberSavedFraction, 
							 TruncRoundValue, Notes, CurrencyID, ServerDate,ClientActive,CID)
	SELECT        Companies.ID, @SalesmanNo AS Expr3, Companies.Name AS Ar,  Companies.Reference1 AS En, Companies.Address AS Add1, 
							 Companies.POBox AS Add2, Companies.ShortName AS Add3, Companies.Email AS Add4, Companies.TelephoneNo, 
							 CASE WHEN @ClientActive = 40 THEN Companies.Reference2 ELSE Companies.TelephoneNo END AS Tel2, Companies.FaxNo, Companies.WebSite AS tlx, 
							 CASE WHEN @ClientActive = 35 THEN Companies.Logo2 ELSE Companies.Logo END AS Expr4, Companies.SalesTaxNum, ISNULL(CompanyParameters.NumberSavedFraction, - 1) AS Expr1, 
							 ISNULL(CompanyParameters.TruncRoundValue, - 1) AS Expr2, Companies.Notes, Companies.CurrencyID,
							 CAST(Day(GetDate()) AS varchar(2)) + '-' + CAST(Month(GetDate()) AS varchar(2)) + '-' + CAST(Year(GetDate()) AS varchar(4)) + ' ' +
							 CAST(DATEPART(HOUR, GETDATE()) AS varchar(4)) + ':' + CAST(DATEPART(MINUTE, GETDATE()) AS varchar(4)) + ':' + CAST(DATEPART(Second, GETDATE()) AS varchar(4)) ,
							 @ClientActive,CID
	FROM            Companies LEFT OUTER JOIN
							 CompanyParameters ON Companies.ID = CompanyParameters.CompanyID	
END


IF @ClientActive = 111 -- Hayat
BEGIN
	INSERT INTO OSFA_DB.dbo.OT_COMPANY
							 (comp_num, SalesmanNo, comp_name, comp_ename, comp_addr1, comp_eaddr1, comp_addr2, comp_eaddr2, comp_tel1, comp_tel2, comp_fax, comp_tlx, comp_logo, SalesTaxNo, NumberSavedFraction, 
							 TruncRoundValue, Notes, CurrencyID, ServerDate,ClientActive,CID)
	SELECT        Companies.ID, @SalesmanNo AS Expr3, Companies.Name AS Ar,  Companies.ShortName AS En, Companies.Address AS Add1, 
							 Companies.POBox AS Add2, Companies.ShortName AS Add3, Companies.Email AS Add4, Companies.TelephoneNo, 
							  Companies.FaxNo  AS Tel2, Companies.FaxNo, Companies.WebSite AS tlx, 
							  Companies.Logo  AS Expr4, Companies.SalesTaxNum, 2AS Expr1, 
							 ISNULL(CompanyParameters.TruncRoundValue, - 1) AS Expr2, Companies.Notes, Companies.CurrencyID,
							 CAST(Day(GetDate()) AS varchar(2)) + '-' + CAST(Month(GetDate()) AS varchar(2)) + '-' + CAST(Year(GetDate()) AS varchar(4)) + ' ' +
							 CAST(DATEPART(HOUR, GETDATE()) AS varchar(4)) + ':' + CAST(DATEPART(MINUTE, GETDATE()) AS varchar(4)) + ':' + CAST(DATEPART(Second, GETDATE()) AS varchar(4)) ,
							 @ClientActive,CID
	FROM            Companies LEFT OUTER JOIN
							 CompanyParameters ON Companies.ID = CompanyParameters.CompanyID	

							 	 Update  OSFA_DB.dbo.OT_COMPANY
							 set comp_addr1= Companies.Address
							 from OSFA_DB.dbo.OT_COMPANY as OT_COMPANY inner join Companies on OT_COMPANY.comp_num = Companies.ID
							 where OT_COMPANY.SalesmanNo=@SalesmanNo
END		
else IF @ClientActive = 118
BEGIN

--if @CompNo=10
--Begin

--	INSERT INTO OSFA_DB.dbo.OT_COMPANY
--							 (comp_num, SalesmanNo, comp_name, comp_ename, comp_addr1, comp_eaddr1, comp_addr2, comp_eaddr2, comp_tel1, comp_tel2, comp_fax, comp_tlx, comp_logo, SalesTaxNo, NumberSavedFraction, 
--							 TruncRoundValue, Notes, CurrencyID, ServerDate)
--	SELECT        Companies.ID, @SalesmanNo AS Expr3, Companies.Name AS Ar,  Companies.Reference1 AS En, Companies.Address AS Add1, 
--							 Companies.POBox AS Add2, Companies.ShortName AS Add3, Companies.Email AS Add4, Companies.TelephoneNo, 
--							 CASE WHEN @ClientActive = 40 THEN Companies.Reference2 ELSE Companies.TelephoneNo END AS Tel2, Companies.FaxNo, Companies.WebSite AS tlx, 
--							 CASE WHEN @ClientActive = 35 THEN Companies.Logo2 ELSE Companies.Logo END AS Expr4, Companies.SalesTaxNum, ISNULL(CompanyParameters.NumberSavedFraction, - 1) AS Expr1, 
--							 ISNULL(CompanyParameters.TruncRoundValue, - 1) AS Expr2, Companies.Notes, Companies.CurrencyID,
--							 CAST(Day(GetDate()) AS varchar(2)) + '-' + CAST(Month(GetDate()) AS varchar(2)) + '-' + CAST(Year(GetDate()) AS varchar(4)) + ' ' +
--							 CAST(DATEPART(HOUR, GETDATE()) AS varchar(4)) + ':' + CAST(DATEPART(MINUTE, GETDATE()) AS varchar(4)) + ':' + CAST(DATEPART(Second, GETDATE()) AS varchar(4)) 
								   
--	FROM            Companies LEFT OUTER JOIN
--							 CompanyParameters ON Companies.ID = CompanyParameters.CompanyID	
--								 where Companies.id =10


--end
--else
--Begin
	INSERT INTO OSFA_DB.dbo.OT_COMPANY
							 (comp_num, SalesmanNo, comp_name, comp_ename, comp_addr1, comp_eaddr1, comp_addr2, comp_eaddr2, comp_tel1, comp_tel2, comp_fax, comp_tlx, comp_logo, SalesTaxNo, NumberSavedFraction, 
							 TruncRoundValue, Notes, CurrencyID, ServerDate)
	SELECT        Companies.ID, @SalesmanNo AS Expr3, Companies.Name AS Ar,  Companies.Reference1 AS En, Companies.Address AS Add1, 
							 Companies.POBox AS Add2, Companies.ShortName AS Add3, Companies.Email AS Add4, Companies.TelephoneNo, 
							 CASE WHEN @ClientActive = 40 THEN Companies.Reference2 ELSE Companies.TelephoneNo END AS Tel2, Companies.FaxNo, Companies.WebSite AS tlx, 
							 CASE WHEN @ClientActive = 35 THEN Companies.Logo2 ELSE Companies.Logo END AS Expr4, Companies.SalesTaxNum, ISNULL(CompanyParameters.NumberSavedFraction, - 1) AS Expr1, 
							 ISNULL(CompanyParameters.TruncRoundValue, - 1) AS Expr2, Companies.Notes, Companies.CurrencyID,
							 CAST(Day(GetDate()) AS varchar(2)) + '-' + CAST(Month(GetDate()) AS varchar(2)) + '-' + CAST(Year(GetDate()) AS varchar(4)) + ' ' +
							 CAST(DATEPART(HOUR, GETDATE()) AS varchar(4)) + ':' + CAST(DATEPART(MINUTE, GETDATE()) AS varchar(4)) + ':' + CAST(DATEPART(Second, GETDATE()) AS varchar(4)) 
								   
	FROM            Companies LEFT OUTER JOIN
							 CompanyParameters ON Companies.ID = CompanyParameters.CompanyID	
							 where Companies.id <>10

	End									
		--end
else if @ClientActive=165
Begin
INSERT INTO OSFA_DB.dbo.OT_COMPANY
							 (comp_num, SalesmanNo, comp_name, comp_ename, comp_addr1, comp_eaddr1, comp_addr2, comp_eaddr2, comp_tel1, comp_tel2, comp_fax, comp_tlx, comp_logo, SalesTaxNo, NumberSavedFraction, 
							 TruncRoundValue, Notes, CurrencyID, ServerDate,ClientActive,CID)
	SELECT        Companies.ID, @SalesmanNo AS Expr3, CASE WHEN @ClientActive = 165 THEN Companies.ShortName ELSE Companies.Name END AS Ar, CASE WHEN @ClientActive = 35 THEN Companies.Reference1 ELSE CASE WHEN @ClientActive = 165 THEN Companies.Name ELSE Companies.Notes END END AS En, Companies.Address AS Add1, 
							 Companies.Reference1 AS Add2, Companies.ShortName AS Add3, Companies.Email AS Add4, Companies.TelephoneNo, 
							 CASE WHEN @ClientActive = 40 THEN Companies.Reference2 WHEN @ClientActive = 64 THEN address WHEN @ClientActive = 136 THEN FaxNo   ELSE Companies.TelephoneNo END AS Tel2, Companies.FaxNo, Companies.WebSite AS tlx, 
							 CASE WHEN @ClientActive = 35 THEN Companies.Logo2 ELSE CASE WHEN @ClientActive = 158 THEN null ELSE Companies.Logo END END AS Expr4, Companies.SalesTaxNum, ISNULL(CompanyParameters.NumberSavedFraction, - 1) AS Expr1, 
							 ISNULL(CompanyParameters.TruncRoundValue, - 1) AS Expr2, Companies.Notes, Companies.CurrencyID,
							 CAST(Day(GetDate()) AS varchar(2)) + '-' + CAST(Month(GetDate()) AS varchar(2)) + '-' + CAST(Year(GetDate()) AS varchar(4)) + ' ' +
							 CAST(DATEPART(HOUR, GETDATE()) AS varchar(4)) + ':' + CAST(DATEPART(MINUTE, GETDATE()) AS varchar(4)) + ':' + CAST(DATEPART(Second, GETDATE()) AS varchar(4)) ,
							 @ClientActive,Companies.CID
	FROM            Companies LEFT OUTER JOIN
							 CompanyParameters ON Companies.ID = CompanyParameters.CompanyID
	WHERE        (Companies.ID = @CompNo)
End


ELSE

BEGIN
	INSERT INTO OSFA_DB.dbo.OT_COMPANY
							 (comp_num, SalesmanNo, comp_name, comp_ename, comp_addr1, comp_eaddr1, comp_addr2, comp_eaddr2, comp_tel1, comp_tel2, comp_fax, comp_tlx, comp_logo, SalesTaxNo, NumberSavedFraction, 
							 TruncRoundValue, Notes, CurrencyID, ServerDate,ClientActive,CID)
	SELECT        Companies.ID, @SalesmanNo AS Expr3, CASE WHEN @ClientActive = 158 AND @SalesmanNo = 5 THEN '' ELSE Companies.Name END AS Ar, CASE WHEN @ClientActive = 35 THEN Companies.Reference1 ELSE CASE WHEN @ClientActive = 16 THEN Companies.Name ELSE Companies.Notes END END AS En, Companies.Address AS Add1, 
							 Companies.POBox AS Add2, Companies.ShortName AS Add3, Companies.Email AS Add4, Companies.TelephoneNo, 
							 CASE WHEN @ClientActive = 40 THEN Companies.Reference2 WHEN @ClientActive = 64 THEN address WHEN @ClientActive = 136 THEN FaxNo   ELSE Companies.TelephoneNo END AS Tel2, Companies.FaxNo, Companies.WebSite AS tlx, 
							 CASE WHEN @ClientActive = 35 THEN Companies.Logo2 ELSE CASE WHEN @ClientActive = 158 THEN null ELSE Companies.Logo END END AS Expr4, Companies.SalesTaxNum, ISNULL(CompanyParameters.NumberSavedFraction, - 1) AS Expr1, 
							 ISNULL(CompanyParameters.TruncRoundValue, - 1) AS Expr2, Companies.Notes, Companies.CurrencyID,
							 CAST(Day(GetDate()) AS varchar(2)) + '-' + CAST(Month(GetDate()) AS varchar(2)) + '-' + CAST(Year(GetDate()) AS varchar(4)) + ' ' +
							 CAST(DATEPART(HOUR, GETDATE()) AS varchar(4)) + ':' + CAST(DATEPART(MINUTE, GETDATE()) AS varchar(4)) + ':' + CAST(DATEPART(Second, GETDATE()) AS varchar(4)) ,
							 @ClientActive,Companies.CID
	FROM            Companies LEFT OUTER JOIN
							 CompanyParameters ON Companies.ID = CompanyParameters.CompanyID
	WHERE        (Companies.ID = @CompNo)
END
if @ClientActive=136
begin
INSERT INTO [OSFA_DB].[dbo].[OT_CustType]
           ([CompNo]
		   ,[SalesmanNo]
           ,[TypeNo]
           ,[ArDesc]
           ,[EngDesc])
SELECT     CompanyID,@SalesmanNo, ID, cast (ID as nvarchar) + '- ' + Name AS Ar, cast (ID as nvarchar)+ '- ' + Name  AS En
FROM         Locations
WHERE     (CompanyID = @CompNo) 
end

else if @ClientActive=16
begin


INSERT INTO [OSFA_DB].[dbo].[OT_CustType]
           ([CompNo]
		   ,[SalesmanNo]
           ,[TypeNo]
           ,[ArDesc]
           ,[EngDesc])
SELECT    distinct    CustomersTypes.CompanyID, @SalesmanNo AS Expr1, CustomersTypes.ID, CustomersTypes.Name AS Ar, CustomersTypes.Name AS En
FROM            CustomersTypes INNER JOIN
                         Customers ON CustomersTypes.CompanyID = Customers.CompanyID AND CustomersTypes.ID = Customers.TypeID
WHERE        (CustomersTypes.CompanyID = @CompNo)
end

else
begin


INSERT INTO [OSFA_DB].[dbo].[OT_CustType]
           ([CompNo]
		   ,[SalesmanNo]
           ,[TypeNo]
           ,[ArDesc]
           ,[EngDesc])
SELECT     CompanyID,@SalesmanNo, ID, Name AS Ar, Name AS En
FROM         CustomersTypes
WHERE     (CompanyID = @CompNo) 
end
if @ClientActive = 74 
Begin
INSERT INTO [OSFA_DB].[dbo].[OT_DocTypes]
           ([CompNo]
		   ,[SalesmanNo]
           ,[VouType]
           ,[DocType]
           ,[ArDesc]
           ,[EngDesc]
		   ,[Ref1]
		   ,[Ref2])
SELECT     distinct   DocumentsTypes.CompanyID, @SalesmanNo AS Expr1, TransactionsTypes.ID, DocumentsTypes.ID AS Expr2, DocumentsTypes.Name AS Ar, 0 AS En, 
                         DocumentsTypes.Notes, '' AS Expr3
FROM            DocumentsTypes INNER JOIN
                         TransactionsTypes ON DocumentsTypes.TransactionTypeID = TransactionsTypes.ID INNER JOIN
                         SalesPersons ON DocumentsTypes.CompanyID = SalesPersons.CompanyID AND  SalesPersons.SerialRef like'%'+DocumentsTypes.Reference1+'%' 
WHERE        (DocumentsTypes.CompanyID = @CompNo) AND (ISNULL(DocumentsTypes.IsSuspended, 0) = 0) and (SalesPersons.id= @SalesmanNo)
End

Else if @ClientActive=118 
Begin
INSERT INTO [OSFA_DB].[dbo].[OT_DocTypes]
           ([CompNo]
		   ,[SalesmanNo]
           ,[VouType]
           ,[DocType]
           ,[ArDesc]
           ,[EngDesc]
		   ,[Ref1]
		   ,[Ref2])
SELECT        DocumentsTypes.CompanyID, @SalesmanNo AS Expr1, TransactionsTypes.ID, DocumentsTypes.ID AS Expr2, DocumentsTypes.Name AS Ar, CASE WHEN @ClientActive = 3 OR @ClientActive = 67 THEN Reference1 ELSE 0 END AS En, 
                         DocumentsTypes.Notes,''
FROM            DocumentsTypes INNER JOIN
                         TransactionsTypes ON DocumentsTypes.TransactionTypeID = TransactionsTypes.ID
WHERE        (DocumentsTypes.CompanyID = @CompNo) And (isnull(Documentstypes.issuspended,0)=0) and TransactionsTypes.ID <>1
 


INSERT INTO [OSFA_DB].[dbo].[OT_DocTypes]
           ([CompNo]
		   ,[SalesmanNo]
           ,[VouType]
           ,[DocType]
           ,[ArDesc]

           ,[EngDesc]
		   ,[Ref1]
		   ,[Ref2])

SELECT        DocumentsTypes.CompanyID, @SalesmanNo AS Expr1, TransactionsTypes.ID, DocumentsTypes.ID AS Expr2, DocumentsTypes.Name AS Ar, CASE WHEN 22 = 3 THEN Reference1 ELSE 0 END AS En, 
                         DocumentsTypes.Notes,''
FROM            DocumentsTypes INNER JOIN
                         TransactionsTypes ON DocumentsTypes.TransactionTypeID = TransactionsTypes.ID
WHERE        (DocumentsTypes.CompanyID = @CompNo) And (isnull(Documentstypes.issuspended,0)=0) and cast(DocumentsTypes.ID as nvarchar(50)) in (
select t from (
(select 
SUBSTRING(Email,1,CHARINDEX(',',case when  Email not like'%,%' then Email+',' else Email End)-1) as t
from SalesPersons where CompanyID= @CompNo and id=@SalesmanNo)
Union All 
(select ISNULL(SUBSTRING(Email,3,CHARINDEX(',',case when  Email not like'%,%' then Email+',' else Email End)+3),'') as t
from SalesPersons where CompanyID= @CompNo and id=@SalesmanNo)) as xbt
) and TransactionsTypes.ID=1


End
Else if @ClientActive = 111
Begin
INSERT INTO [OSFA_DB].[dbo].[OT_DocTypes]
           ([CompNo]
		   ,[SalesmanNo]
           ,[VouType]
           ,[DocType]
           ,[ArDesc]
           ,[EngDesc]
		   ,[Ref1]
		   ,[Ref2])

SELECT        DocumentsTypes.CompanyID, @SalesmanNo AS Expr1, TransactionsTypes.ID, DocumentsTypes.ID AS Expr2, DocumentsTypes.Name AS Ar,  '0' AS  En, 
                         DocumentsTypes.Notes, '' AS Expr3
FROM            DocumentsTypes INNER JOIN
                         TransactionsTypes ON DocumentsTypes.TransactionTypeID = TransactionsTypes.ID INNER JOIN
                         SalesPersons ON SalesPersons.Email like'%'+DocumentsTypes.Reference2+'%'  AND DocumentsTypes.CompanyID = SalesPersons.CompanyID AND DocumentsTypes.TransactionTypeID = 3
WHERE        (DocumentsTypes.CompanyID = @CompNo) AND (ISNULL(DocumentsTypes.IsSuspended, 0) = 0)  AND SalesPersons.ID =@SalesmanNo

UNION ALL 

SELECT        DocumentsTypes.CompanyID, @SalesmanNo AS Expr1, TransactionsTypes.ID, DocumentsTypes.ID AS Expr2, DocumentsTypes.Name AS Ar,'0' AS En, 
                         DocumentsTypes.Notes,''
FROM            DocumentsTypes INNER JOIN
                         TransactionsTypes ON DocumentsTypes.TransactionTypeID = TransactionsTypes.ID
WHERE        (DocumentsTypes.CompanyID = @CompNo) And (isnull(Documentstypes.issuspended,0)=0)  AND DocumentsTypes.TransactionTypeID <> 3

End						   
Else
Begin
INSERT INTO [OSFA_DB].[dbo].[OT_DocTypes]
           ([CompNo]
		   ,[SalesmanNo]
           ,[VouType]
           ,[DocType]
           ,[ArDesc]
           ,[EngDesc]
		   ,[Ref1]
		   ,[Ref2])
SELECT        DocumentsTypes.CompanyID, @SalesmanNo AS Expr1, TransactionsTypes.ID, DocumentsTypes.ID AS Expr2, DocumentsTypes.Name AS Ar, CASE WHEN @ClientActive = 3 or @ClientActive=67 THEN Reference1 ELSE 0 END AS En, 
                         DocumentsTypes.Notes,''
FROM            DocumentsTypes INNER JOIN
                         TransactionsTypes ON DocumentsTypes.TransactionTypeID = TransactionsTypes.ID
WHERE        (DocumentsTypes.CompanyID = @CompNo) And (isnull(Documentstypes.issuspended,0)=0)

End

INSERT INTO [OSFA_DB].[dbo].[OT_GeoLevel1]
           ([CompNo]
		   ,[SalesmanNo]
		   ,[GeoLevel1]		   
           ,[ArDesc]
           ,[EngDesc])
SELECT     @CompNo, @SalesmanNo, ID, dbo.Fun_GetLocationFullPath(@CompNo,ID,'-'), Name AS En
FROM         Locations
WHERE     (CompanyID = @CompNo)  


SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_COMPANY, OT_CustType, OT_DocTypes, OT_GeoLevel1 [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

SET @BeginTime = Convert(varchar(20),GetDate(),108)

If  @ClientActive =30
BEGIN 


INSERT INTO OSFA_DB.dbo.OT_ItemsCateg
                         (CompNo, SalesmanNo, Categ, CategName, CategNameEng,[CategSort])
VALUES        (@CompNo,@SalesmanNo,'01','All Zoumt Items','All Zoumt Items',0)


INSERT INTO OSFA_DB.dbo.OT_ItemsSubCateg
                         (CompNo, SalesmanNo, Categ, SubCateg, SubCategName, SubCategNameEng)
VALUES        (@CompNo,@SalesmanNo,'01','01-01','All Zoumt Items','All Zoumt Items')

END 


ELSE if @ClientActive=95
BEGIN 

INSERT INTO [OSFA_DB].[dbo].[OT_ItemsCateg]
           ([CompNo]
		   ,[SalesmanNo]
           ,[Categ]
           ,[CategName]
           ,[CategNameEng])
SELECT     CompanyID, @SalesmanNo, CategCode, case when @ClientActive=95 then ShortName else   Name  end  AS Ar, ForeignName AS En
FROM         ItemsCategories
WHERE     (CompanyID = @CompNo) AND ([Level] = @ItemCategLevel-1)

INSERT INTO [OSFA_DB].[dbo].[OT_ItemsSubCateg]
           ([CompNo]
		   ,[SalesmanNo]
           ,[Categ]
           ,[SubCateg]
           ,[SubCategName]
           ,[SubCategNameEng])           
SELECT     CompanyID, @SalesmanNo, ISNULL(Parent,CategCode) AS M, CategCode AS Sub, case when @ClientActive=95 then ShortName else   Name  end  AS Ar, Name AS En
FROM         ItemsCategories
WHERE     (CompanyID = @CompNo) AND ([Level] = @ItemCategLevel)

IF NOT EXISTS(SELECT * FROM [OSFA_DB].[dbo].[OT_ItemsCateg]  WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo))
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_ItemsCateg]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[Categ]
			   ,[CategName]
			   ,[CategNameEng])
	SELECT     CompanyID, @SalesmanNo, CategCode, case when @ClientActive=85 then ForeignName else   Name  end  AS Ar, ForeignName AS En
	FROM         ItemsCategories
	WHERE     (CompanyID = @CompNo) AND ([Level] = @ItemCategLevel)
	
	UPDATE  [OSFA_DB].[dbo].[OT_ItemsSubCateg] SET  [Categ]=[SubCateg] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
END 
END 

ELSE if @ClientActive=24
BEGIN 

INSERT INTO [OSFA_DB].[dbo].[OT_ItemsCateg]
           ([CompNo]
		   ,[SalesmanNo]
           ,[Categ]
           ,[CategName]
           ,[CategNameEng],[CategSort])
SELECT     CompanyID, @SalesmanNo, CategCode, case when @ClientActive=85 then ForeignName else   Name  end  AS Ar, ForeignName AS En,[CategSort]
FROM         ItemsCategories
WHERE     (CompanyID = @CompNo) AND ([Level] = @ItemCategLevel-1) and ISNULL(ItemsCategories.IsSuspended,0)=0

INSERT INTO [OSFA_DB].[dbo].[OT_ItemsSubCateg]
           ([CompNo]
		   ,[SalesmanNo]
           ,[Categ]
           ,[SubCateg]
           ,[SubCategName]
           ,[SubCategNameEng])           
SELECT     CompanyID, @SalesmanNo, ISNULL(Parent,CategCode) AS M, CategCode AS Sub, case when @ClientActive=85 then ForeignName else   Name  end  AS Ar, Name AS En
FROM         ItemsCategories
WHERE     (CompanyID = @CompNo) AND ([Level] = @ItemCategLevel)  and ISNULL(ItemsCategories.IsSuspended,0)=0

IF NOT EXISTS(SELECT * FROM [OSFA_DB].[dbo].[OT_ItemsCateg]  WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo))
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_ItemsCateg]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[Categ]
			   ,[CategName]
			   ,[CategNameEng],[CategSort])
	SELECT     CompanyID, @SalesmanNo, CategCode, case when @ClientActive=85 then ForeignName else   Name  end  + '****'AS Ar, ForeignName AS En,[CategSort]
	FROM         ItemsCategories
	WHERE     (CompanyID = @CompNo) AND ([Level] = @ItemCategLevel) and ISNULL(ItemsCategories.IsSuspended,0)=0
	
	UPDATE  [OSFA_DB].[dbo].[OT_ItemsSubCateg] SET  [Categ]=[SubCateg] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
END 
END 

ELSE 
BEGIN 
PRINT 'AXAXAXAAXAXAXAAXAXAXAXAXAXA'
INSERT INTO [OSFA_DB].[dbo].[OT_ItemsCateg]
           ([CompNo]
		   ,[SalesmanNo]
           ,[Categ]
           ,[CategName]
           ,[CategNameEng],[CategSort])
SELECT     CompanyID, @SalesmanNo, CategCode, case when @ClientActive=85 then ForeignName else   Name  end  AS Ar, ForeignName AS En,[CategSort]
FROM         ItemsCategories
WHERE     (CompanyID = @CompNo) AND ([Level] = @ItemCategLevel-1)

INSERT INTO [OSFA_DB].[dbo].[OT_ItemsSubCateg]
           ([CompNo]
		   ,[SalesmanNo]
           ,[Categ]
           ,[SubCateg]
           ,[SubCategName]
           ,[SubCategNameEng])           
SELECT     CompanyID, @SalesmanNo, ISNULL(Parent,CategCode) AS M, CategCode AS Sub, case when @ClientActive=85 then ForeignName else   Name  end  AS Ar, Name AS En
FROM         ItemsCategories
WHERE     (CompanyID = @CompNo) AND ([Level] = @ItemCategLevel)

IF NOT EXISTS(SELECT * FROM [OSFA_DB].[dbo].[OT_ItemsCateg]  WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo))
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_ItemsCateg]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[Categ]
			   ,[CategName]
			   ,[CategNameEng],[CategSort])
	SELECT     CompanyID, @SalesmanNo, CategCode, case when @ClientActive=85 then ForeignName else   Name  end  + '****'AS Ar, ForeignName AS En,[CategSort]
	FROM         ItemsCategories
	WHERE     (CompanyID = @CompNo) AND ([Level] = @ItemCategLevel)
	
	UPDATE  [OSFA_DB].[dbo].[OT_ItemsSubCateg] SET  [Categ]=[SubCateg] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
END 
END 

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_ItemsCateg, OT_ItemsSubCateg [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
/*
SET @BeginTime = Convert(varchar(20),GetDate(),108)

INSERT INTO [OSFA_DB].[dbo].[OT_PromotionsHeaders]
           ([CompNo]
		   ,[SalesmanNo]
           ,[PromotionCode]
           ,[PromotionType]
           ,[PromotionName]
           ,[Ref1]
           ,[Ref2]
           ,[StartDate]
           ,[EndDate]
           ,[IsSuspended]
           ,[InputItemUnit]
           ,[InputQtyAmount]
           ,[OutPutType]
           ,[OutItemUnit]
           ,[OutQtyAmount]
           ,[OutQtyAmount_2]
           ,[UseInReturn]
           ,[UseInSales]
           ,PromotionDetails
           ,UseRateToCalcBonus
           ,NotDouble
           ,ApplyForAllUnit
           ,[DiscountType]
           ,[IncludeInTargetBonus]
           ,[PriorityID]
           ,[PrioritySerial]
		   ,RoundType
		   ,IsNeedCoupon
		   ,InvoiceType
		   ,RunAfterAllPromos
		   ,OutPutSameInput
			,SalesmanCanChangeOutPutQty
			,IsAmountWithoutTax
			,NeedWorkFlowApproval)
           
SELECT        PromotionsHeaders.CompanyID, @SalesmanNo AS SalesmanNo, PromotionsHeaders.ID, PromotionsHeaders.PromotionType, PromotionsHeaders.Name, PromotionsHeaders.Reference1, 
                         PromotionsHeaders.Reference2, PromotionsHeaders.StartDate, PromotionsHeaders.EndDate, PromotionsHeaders.IsSuspended, ItemsUnits.ID AS IIU, PromotionsHeaders.InputQtyAmount, 
                         PromotionsHeaders.OutPutType, ItemsUnits_1.ID AS OIU, PromotionsHeaders.OutQtyAmount, PromotionsHeaders.OutQtyAmount_2, PromotionsHeaders.UseInReturn, PromotionsHeaders.UseInSales, 
                         PromotionsHeaders.PromotionDetails, PromotionsHeaders.UseRateToCalcBonus, ISNULL(PromotionsHeaders.NotDouble, 0) AS Expr2, ISNULL(PromotionsHeaders.ApplyForAllUnit, 0) AS Expr3, 
                         ISNULL(PromotionsHeaders.DiscountType, 0) AS Expr1, ISNULL(PromotionsHeaders.IncludeInTargetBonus, 0) AS Expr4, ISNULL(PromotionsPrioritiesLink.PriorityID, 0) AS Expr5, 
                         ISNULL(PromotionsPrioritiesLink.PrioritySerial, 0) AS Expr6, ISNULL(PromotionsHeaders.RoundType, 3) AS RoundType, PromotionsHeaders.IsNeedCoupon, IsNUll(PromotionsHeaders.InvoiceType,-1) AS InvoiceType, IsNUll(PromotionsHeaders.RunAfterAllPromos,0) AS RunAfterAllPromos
						, ISNULL(OutPutSameInput, 0) , ISNULL(SalesmanCanChangeOutPutQty, 0), ISNULL(IsAmountWithoutTax, 0), ISNULL(NeedWorkFlowApproval,0)
FROM            PromotionsHeaders INNER JOIN
                         PromotionsSalesmanGroupsLink ON PromotionsHeaders.CompanyID = PromotionsSalesmanGroupsLink.CompanyID AND PromotionsHeaders.ID = PromotionsSalesmanGroupsLink.PromotionID INNER JOIN
                         SalesPersons ON PromotionsSalesmanGroupsLink.CompanyID = SalesPersons.CompanyID AND PromotionsSalesmanGroupsLink.SalesPersonsGroupID IN(SalesPersons.GroupID, ISNULL(@SalesmanPromGroup,-1)) LEFT OUTER JOIN
                         PromotionsPrioritiesLink ON PromotionsHeaders.CompanyID = PromotionsPrioritiesLink.CompanyID AND PromotionsHeaders.ID = PromotionsPrioritiesLink.PromotionID LEFT OUTER JOIN
                         ItemsUnits AS ItemsUnits_1 ON PromotionsHeaders.OutItemUnitID = ItemsUnits_1.ID AND PromotionsHeaders.CompanyID = ItemsUnits_1.CompanyID LEFT OUTER JOIN
                         ItemsUnits ON PromotionsHeaders.InputItemUnitID = ItemsUnits.ID AND PromotionsHeaders.CompanyID = ItemsUnits.CompanyID
WHERE        (PromotionsHeaders.CompanyID = @CompNo) AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, PromotionsHeaders.StartDate)) <= @SendDate) AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, 
                         PromotionsHeaders.EndDate)) >= @SendDate) AND (PromotionsHeaders.IsSuspended = 0) AND (SalesPersons.ID = @SalesmanNo)

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_PromotionsHeaders [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')


SET @BeginTime = Convert(varchar(20),GetDate(),108)

INSERT INTO [OSFA_DB].[dbo].[OT_PromotionsCondUnCodInput]
           ([CompNo]
		   ,[SalesmanNo]
           ,[PromotionCode]
           ,[ItemNo]
           ,[Unit]
           ,[Qty]
		   ,[ItemSerial]
		   ,[InputType]
		   ,[ToQty])
SELECT        PromotionsCondUnCodInput.CompanyID, @SalesmanNo AS Salesman, PromotionsCondUnCodInput.PromotionID, Items.ItemCode, ItemsUnits.ID AS UnitID, PromotionsCondUnCodInput.Quantity, 
                         PromotionsCondUnCodInput.ItemSerial,PromotionsCondUnCodInput.[InputType],PromotionsCondUnCodInput.ToQuantity
FROM            PromotionsCondUnCodInput INNER JOIN
                         PromotionsHeaders ON PromotionsCondUnCodInput.CompanyID = PromotionsHeaders.CompanyID AND PromotionsCondUnCodInput.PromotionID = PromotionsHeaders.ID INNER JOIN
                         Items ON PromotionsCondUnCodInput.CompanyID = Items.CompanyID AND PromotionsCondUnCodInput.ItemCode = Items.ItemCode INNER JOIN
                         PromotionsSalesmanGroupsLink ON PromotionsHeaders.CompanyID = PromotionsSalesmanGroupsLink.CompanyID AND PromotionsHeaders.ID = PromotionsSalesmanGroupsLink.PromotionID INNER JOIN
                         SalesPersons ON PromotionsSalesmanGroupsLink.CompanyID = SalesPersons.CompanyID AND PromotionsSalesmanGroupsLink.SalesPersonsGroupID IN(SalesPersons.GroupID, ISNULL(@SalesmanPromGroup,-1)) LEFT OUTER JOIN
                         ItemsUnits ON PromotionsCondUnCodInput.CompanyID = ItemsUnits.CompanyID AND PromotionsCondUnCodInput.ItemUnitID = ItemsUnits.ID
WHERE        (PromotionsCondUnCodInput.CompanyID = @CompNo) AND (PromotionsHeaders.IsSuspended = 0) AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, PromotionsHeaders.StartDate)) <= @SendDate) AND 
                         (DATEADD(DAY, 0, DATEDIFF(DAY, 0, PromotionsHeaders.EndDate)) >= @SendDate) AND (SalesPersons.ID = @SalesmanNo)

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_PromotionsCondUnCodInput [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

SET @BeginTime = Convert(varchar(20),GetDate(),108)

INSERT INTO [OSFA_DB].[dbo].[OT_PromotionsCondUnCodOutput]
           ([CompNo]
		   ,[SalesmanNo]
           ,[PromotionCode]
           ,[ItemNo]
           ,[ItemUnitID]
           ,[OutQty]
		   ,[ItemSerial]
		   ,OutPutType
		   ,DiscountType
		   ,IsConditional)
SELECT        PromotionsCondUnCodOutput.CompanyID, @SalesmanNo AS SalesmanNo, PromotionsCondUnCodOutput.PromotionID, Items.ItemCode, ItemsUnits.ID AS UnitID, ISNULL(PromotionsCondUnCodOutput.Quantity, 0)
                          AS Qty, PromotionsCondUnCodOutput.ItemSerial,IsNUll(PromotionsCondUnCodOutput.OutPutType,1),PromotionsCondUnCodOutput.DiscountType,PromotionsCondUnCodOutput.IsConditional
FROM            PromotionsCondUnCodOutput INNER JOIN
                         PromotionsHeaders ON PromotionsCondUnCodOutput.CompanyID = PromotionsHeaders.CompanyID AND PromotionsCondUnCodOutput.PromotionID = PromotionsHeaders.ID INNER JOIN
                         Items ON PromotionsCondUnCodOutput.CompanyID = Items.CompanyID AND PromotionsCondUnCodOutput.ItemCode = Items.ItemCode INNER JOIN
                         PromotionsSalesmanGroupsLink ON PromotionsHeaders.CompanyID = PromotionsSalesmanGroupsLink.CompanyID AND PromotionsHeaders.ID = PromotionsSalesmanGroupsLink.PromotionID INNER JOIN
                         SalesPersons ON PromotionsSalesmanGroupsLink.CompanyID = SalesPersons.CompanyID AND PromotionsSalesmanGroupsLink.SalesPersonsGroupID IN(SalesPersons.GroupID, ISNULL(@SalesmanPromGroup,-1)) LEFT OUTER JOIN
                         ItemsUnits ON PromotionsCondUnCodOutput.CompanyID = ItemsUnits.CompanyID AND PromotionsCondUnCodOutput.ItemUnitID = ItemsUnits.ID
WHERE        (PromotionsCondUnCodOutput.CompanyID = @CompNo) AND (PromotionsHeaders.IsSuspended = 0) AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, PromotionsHeaders.StartDate)) <= @SendDate) AND 
                         (DATEADD(DAY, 0, DATEDIFF(DAY, 0, PromotionsHeaders.EndDate)) >= @SendDate) AND (SalesPersons.ID = @SalesmanNo)

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_PromotionsCondUnCodOutput [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')


SET @BeginTime = Convert(varchar(20),GetDate(),108)

INSERT INTO [OSFA_DB].[dbo].[OT_PromotionsRangeInputOutput]
           ([CompNo]
		   ,[SalesmanNo]
           ,[PromotionCode]
           ,[ItemNo]
           ,[Unit]
           ,[FromQty]
           ,[ToQty]
           ,[OutputQty]
           ,[Serial])
SELECT        PromotionsRangeInput.CompanyID, @SalesmanNo AS SalesmanNo, PromotionsRangeInput.PromotionID, Items.ItemCode, ItemsUnits.ID AS UnitID, PromotionsRangeInput.FromQuantity, 
                         PromotionsRangeInput.ToQuantity, PromotionsRangeInput.OutputQuantity, 0 AS Expr1
FROM            PromotionsRangeInput INNER JOIN
                         PromotionsHeaders ON PromotionsRangeInput.CompanyID = PromotionsHeaders.CompanyID AND PromotionsRangeInput.PromotionID = PromotionsHeaders.ID INNER JOIN
                         Items ON PromotionsRangeInput.CompanyID = Items.CompanyID AND PromotionsRangeInput.ItemCode = Items.ItemCode INNER JOIN
                         PromotionsSalesmanGroupsLink ON PromotionsHeaders.CompanyID = PromotionsSalesmanGroupsLink.CompanyID AND PromotionsHeaders.ID = PromotionsSalesmanGroupsLink.PromotionID INNER JOIN
                         SalesPersons ON PromotionsSalesmanGroupsLink.CompanyID = SalesPersons.CompanyID AND PromotionsSalesmanGroupsLink.SalesPersonsGroupID IN(SalesPersons.GroupID, ISNULL(@SalesmanPromGroup,-1)) LEFT OUTER JOIN
                         ItemsUnits ON PromotionsRangeInput.CompanyID = ItemsUnits.CompanyID AND PromotionsRangeInput.ItemUnitID = ItemsUnits.ID
WHERE        (PromotionsRangeInput.CompanyID = @CompNo) AND (PromotionsHeaders.IsSuspended = 0) AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, PromotionsHeaders.StartDate)) <= @SendDate) AND (DATEADD(DAY, 0, 
                         DATEDIFF(DAY, 0, PromotionsHeaders.EndDate)) >= @SendDate) AND (SalesPersons.ID = @SalesmanNo)

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_PromotionsRangeInputOutput [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

*/

/*
SET @BeginTime = Convert(varchar(20),GetDate(),108)

INSERT INTO [OSFA_DB].[dbo].[OT_PromotionsSalesmanGroupsLink]
           ([CompNo]
		   ,[SalesmanNo]
           ,[PromotionCode]
           ,[SalesmanGroup_ID])
SELECT        PromotionsSalesmanGroupsLink.CompanyID, @SalesmanNo AS SalesmanNo, PromotionsSalesmanGroupsLink.PromotionID, PromotionsSalesmanGroupsLink.SalesPersonsGroupID
FROM            PromotionsSalesmanGroupsLink INNER JOIN
                         PromotionsHeaders ON PromotionsSalesmanGroupsLink.CompanyID = PromotionsHeaders.CompanyID AND PromotionsSalesmanGroupsLink.PromotionID = PromotionsHeaders.ID INNER JOIN
                         SalesPersons ON PromotionsSalesmanGroupsLink.CompanyID = SalesPersons.CompanyID AND PromotionsSalesmanGroupsLink.SalesPersonsGroupID IN(SalesPersons.GroupID, ISNULL(@SalesmanPromGroup,-1))
WHERE        (PromotionsSalesmanGroupsLink.CompanyID = @CompNo) AND (PromotionsHeaders.IsSuspended = 0) AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, PromotionsHeaders.StartDate)) <= @SendDate) AND 
                         (DATEADD(DAY, 0, DATEDIFF(DAY, 0, PromotionsHeaders.EndDate)) >= @SendDate) AND (SalesPersons.ID = @SalesmanNo)

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_PromotionsSalesmanGroupsLink [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
*/

/*
SET @BeginTime = Convert(varchar(20),GetDate(),108)

INSERT INTO [OSFA_DB].[dbo].[OT_PromotionsCustomersGroupsLink]
           ([CompNo]
		   ,[SalesmanNo]
           ,[PromotionCode]
           ,[Prom_GroupID])
SELECT        PromotionsCustomersGroupsLink.CompanyID, @SalesmanNo AS SalesmanNo, PromotionsCustomersGroupsLink.PromotionID, PromotionsCustomersGroupsLink.CustomersPromotionsGroupsID
FROM            PromotionsCustomersGroupsLink INNER JOIN
                         PromotionsHeaders ON PromotionsCustomersGroupsLink.CompanyID = PromotionsHeaders.CompanyID AND PromotionsCustomersGroupsLink.PromotionID = PromotionsHeaders.ID INNER JOIN
                         PromotionsSalesmanGroupsLink ON PromotionsHeaders.CompanyID = PromotionsSalesmanGroupsLink.CompanyID AND PromotionsHeaders.ID = PromotionsSalesmanGroupsLink.PromotionID INNER JOIN
                         SalesPersons ON PromotionsSalesmanGroupsLink.CompanyID = SalesPersons.CompanyID AND PromotionsSalesmanGroupsLink.SalesPersonsGroupID IN(SalesPersons.GroupID, ISNULL(@SalesmanPromGroup,-1))
WHERE        (PromotionsCustomersGroupsLink.CompanyID = @CompNo) AND (PromotionsHeaders.IsSuspended = 0) AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, PromotionsHeaders.StartDate)) <= @SendDate) AND 
                         (DATEADD(DAY, 0, DATEDIFF(DAY, 0, PromotionsHeaders.EndDate)) >= @SendDate) AND (SalesPersons.ID = @SalesmanNo)

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_PromotionsCustomersGroupsLink [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
*/

SET @BeginTime = Convert(varchar(20),GetDate(),108)

INSERT INTO OSFA_DB.dbo.OT_PriceListsMF
                         (CompNo, SalesmanNo, PrNo, ArDesc, EngDesc, CurrencyID, ExRate)
SELECT        CompanyID, @SalesmanNo AS Expr1, ID, Name,isnull(Notes,'') AS En , CurrencyID, 
					ISNULL((SELECT TOP (1) ExRate FROM CurrenciesRate WHERE (CompanyID = @CompNo) AND (CurrencyID = PriceLists.CurrencyID) AND (ExDate <= @SendDate) ORDER BY ExDate DESC),1) AS ExRate
FROM            PriceLists
WHERE        (CompanyID = @CompNo) AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, StartDate)) <= @SendDate) AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, EndDate)) >= @SendDate) AND (ISNULL(IsSuspended, 0) = 0)

if @ClientActive=68 and @SalesPersonType=7
Begin
select 0
End

else if @ClientActive=74

Begin

INSERT INTO [OSFA_DB].[dbo].[OT_RouteMF]
           ([CompNo]
		   ,[SalesmanNo]
           ,[RouteID]
           ,[RouteDesc]
           ,[GeoLevel1]
           ,[GeoLevel2]
           ,[GeoLevel3]
           ,[GeoLevel4]
           ,[GeoLevel5]
           ,[Notes])
SELECT S.CompanyID, @SalesmanNo AS SalesmaNo, RouteID, R.Name,0,0,0,0,0,''
from SalespersonRouteByDate as S inner join RoutesInformation as R on S.CompanyID=R.companyid
and S.RouteID=R.ID where S.PositionID=@PositionsID
union 
SELECT Xtbl.CompanyID, @SalesmanNo AS SalesmaNo, Xtbl.RouteID, RoutesInformation.Name,0,0,0,0,0,''
FROM(
SELECT CompanyID, Week1 AS RouteID FROM SalesPersonsRoutes WHERE CompanyID = @CompNo AND PositionsID = @PositionsID
UNION
SELECT CompanyID, Week2 FROM SalesPersonsRoutes WHERE CompanyID = @CompNo AND PositionsID = @PositionsID
UNION
SELECT CompanyID, Week3 FROM SalesPersonsRoutes WHERE CompanyID = @CompNo AND PositionsID = @PositionsID
UNION
SELECT CompanyID, Week4 FROM SalesPersonsRoutes WHERE CompanyID = @CompNo AND PositionsID = @PositionsID
) AS Xtbl INNER JOIN RoutesInformation ON Xtbl.CompanyID = RoutesInformation.CompanyID AND Xtbl.RouteID = RoutesInformation.ID
END
else
Begin
INSERT INTO [OSFA_DB].[dbo].[OT_RouteMF]
           ([CompNo]
		   ,[SalesmanNo]
           ,[RouteID]
           ,[RouteDesc]
           ,[GeoLevel1]
           ,[GeoLevel2]
           ,[GeoLevel3]
           ,[GeoLevel4]
           ,[GeoLevel5]
           ,[Notes])
SELECT Xtbl.CompanyID, @SalesmanNo AS SalesmaNo, Xtbl.RouteID, RoutesInformation.Name,0,0,0,0,0,''
FROM(
SELECT CompanyID, Week1 AS RouteID FROM SalesPersonsRoutes WHERE CompanyID = @CompNo AND PositionsID = @PositionsID
UNION
SELECT CompanyID, Week2 FROM SalesPersonsRoutes WHERE CompanyID = @CompNo AND PositionsID = @PositionsID
UNION
SELECT CompanyID, Week3 FROM SalesPersonsRoutes WHERE CompanyID = @CompNo AND PositionsID = @PositionsID
UNION
SELECT CompanyID, Week4 FROM SalesPersonsRoutes WHERE CompanyID = @CompNo AND PositionsID = @PositionsID
) AS Xtbl INNER JOIN RoutesInformation ON Xtbl.CompanyID = RoutesInformation.CompanyID AND Xtbl.RouteID = RoutesInformation.ID
End
--SELECT     CompanyID, @SalesmanNo, ID, Name,0,0,0,0,0,''
--FROM         RoutesInformation 
--WHERE CompanyID =  @CompNo   
/*
IF @ClientActive = 4
begin
	INSERT INTO [OSFA_DB].[dbo].[OT_ItemUnits]
           ([CompNo]
		   ,[SalesmanNo]
           ,[UnitID]
           ,[UnitDesc]
		   ,IsIntegerQty)
     SELECT     CompanyID,@SalesmanNo,ID, Name, ISNULL(IsIntegerQty,0)
	 FROM         ItemsUnits
     WHERE CompanyID =  @CompNo 
end
else
begin*/
	 INSERT INTO [OSFA_DB].[dbo].[OT_ItemUnits]
           ([CompNo]
		   ,[SalesmanNo]
           ,[UnitID]
           ,[UnitDesc]
		   ,IsIntegerQty)
     SELECT     CompanyID,@SalesmanNo,ID, Name, ISNULL(IsIntegerQty,0)
	 FROM         ItemsUnits
     WHERE CompanyID =  @CompNo 
--end  

INSERT INTO [OSFA_DB].[dbo].[OT_PaymentsTypes]
           ([CompNo]
		   ,[SalesmanNo]
           ,[PTypeID]
           ,[PTypeName]
		   ,Ref1
		   ,Ref2
		   ,DueDays)
               SELECT     CompanyID,@SalesmanNo, ID, Name,Reference1,Reference2,ISNULL(DueDays,0)
FROM         PaymentsTypes
WHERE     (CompanyID = @CompNo)                                    
       
SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_PriceListsMF, OT_RouteMF, OT_ItemUnits, OT_PaymentsTypes [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

SET @BeginTime = Convert(varchar(20),GetDate(),108)

INSERT INTO [OSFA_DB].[dbo].[OT_Surveys]
           ([CompNo]
		   ,[SalesmanNo]
           ,[Survey_ID]
           ,[Survey_Name]
           ,[Active]
		   ,[IsRequired],IsSalesmanSurvey
		   )
SELECT        Surveys.CompanyID, SurveySalesPersonsAssignment.SalesPersonsID, Surveys.Survey_ID, Surveys.Survey_Name, Surveys.Active, ISNULL(Surveys.IsRequired,0), ISNULL(Surveys.IsSalesmanSurvey,0)
FROM            Surveys INNER JOIN
                         SurveySalesPersonsAssignment ON Surveys.CompanyID = SurveySalesPersonsAssignment.CompanyID AND Surveys.Survey_ID = SurveySalesPersonsAssignment.Survey_ID
WHERE        (Surveys.CompanyID = @CompNo) AND (Surveys.Active = 1) AND (SurveySalesPersonsAssignment.SalesPersonsID = @SalesmanNo)


INSERT INTO [OSFA_DB].[dbo].[OT_Surveys_Questions]
                      (CompNo,[SalesmanNo], Survey_ID, Question_No, Template_No, Question_String,SortID,RankID,IsRequired)
SELECT        Surveys_Questions.CompanyID, SurveySalesPersonsAssignment.SalesPersonsID, Surveys_Questions.Survey_ID, Surveys_Questions.Question_No, Surveys_Questions.Template_No, 
                         Surveys_Questions.Question_String,ISNULL(SortID,Surveys_Questions.Question_No),ROW_NUMBER() OVER (PARTITION BY Surveys_Questions.Survey_ID ORDER BY Surveys_Questions.Survey_ID, ISNULL(SortID,Surveys_Questions.Question_No)),
						 ISNULL(Surveys_Questions.IsRequired,1) AS IsRequired
FROM            Surveys_Questions INNER JOIN
                         Surveys ON Surveys_Questions.CompanyID = Surveys.CompanyID AND Surveys_Questions.Survey_ID = Surveys.Survey_ID INNER JOIN
                         SurveySalesPersonsAssignment ON Surveys.CompanyID = SurveySalesPersonsAssignment.CompanyID AND Surveys.Survey_ID = SurveySalesPersonsAssignment.Survey_ID
WHERE        (Surveys_Questions.CompanyID = @CompNo) AND (Surveys.Active = 1) AND (SurveySalesPersonsAssignment.SalesPersonsID = @SalesmanNo)


INSERT INTO [OSFA_DB].[dbo].[OT_Surveys_Questions_Options]
           ([CompNo]
		   ,[SalesmanNo]
           ,[Survey_ID]
           ,[Question_No]
           ,[Option_No]
           ,[Option_Desc]
		   ,SortID)
SELECT        Surveys_Questions_Options.CompanyID, SurveySalesPersonsAssignment.SalesPersonsID, Surveys_Questions_Options.Survey_ID, Surveys_Questions_Options.Question_No, 
                         Surveys_Questions_Options.Option_No, Surveys_Questions_Options.Option_Desc,ISNULL(SortID,Surveys_Questions_Options.Option_No)
FROM            Surveys_Questions_Options INNER JOIN
                         Surveys ON Surveys_Questions_Options.CompanyID = Surveys.CompanyID AND Surveys_Questions_Options.Survey_ID = Surveys.Survey_ID INNER JOIN
                         SurveySalesPersonsAssignment ON Surveys.CompanyID = SurveySalesPersonsAssignment.CompanyID AND Surveys.Survey_ID = SurveySalesPersonsAssignment.Survey_ID
WHERE        (Surveys_Questions_Options.CompanyID = @CompNo) AND (Surveys.Active = 1) AND (SurveySalesPersonsAssignment.SalesPersonsID = @SalesmanNo)

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_Surveys, OT_Surveys_Questions, OT_Surveys_Questions_Options [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

SET @BeginTime = Convert(varchar(20),GetDate(),108)

INSERT INTO [OSFA_DB].[dbo].[OT_CompanyBranches]   
			([CompNo]
			,[SalesmanNo]
			,[ID]
			,[Name]
			,[Address])
SELECT        CompanyID, @SalesmanNo, ID, Name, Address
FROM            CompanyBranches
WHERE        (CompanyID = @CompNo)

--//////////////////////////////////////////////////////////////////////////////////////
SELECT        CompNo, Op_ID, SalesmanNo, Op_Desc, Op_Value, Notes
FROM            OSFA_DB.dbo.OT_SystemOptions
WHERE        (CompNo = @CompNo) AND (Op_ID = 68) AND (SalesmanNo = 0)
if @@RowCount = 0
BEGIN
	INSERT INTO OSFA_DB.dbo.OT_SystemOptions(CompNo, Op_ID, SalesmanNo, Op_Desc, Op_Value, Notes)
	VALUES        (@CompNo,68,0,'Serial Type',@SerialType,'0: Stander Serials, 1: Serials By Notebook')
END
ELSE
BEGIN
	UPDATE       OSFA_DB.dbo.OT_SystemOptions
	SET                Op_Value = @SerialType

	WHERE        (CompNo = @CompNo) AND (Op_ID = 68) AND (SalesmanNo = 0)
END

--//////////////////////////////////////////////////////////////////////////////////////
if @ClientActive not in (84,141)
Begin

SELECT        CompNo, Op_ID, SalesmanNo, Op_Desc, Op_Value, Notes
FROM            OSFA_DB.dbo.OT_SystemOptions
WHERE        (CompNo = @CompNo) AND (Op_ID = 100) AND (SalesmanNo = 0)
if @@RowCount = 0
BEGIN
	INSERT INTO OSFA_DB.dbo.OT_SystemOptions(CompNo, Op_ID, SalesmanNo, Op_Desc, Op_Value, Notes)
	VALUES        (@CompNo,100,0,'Use Range Price',@UseRangePrice,'0=Off | 1=On')
END
ELSE
BEGIN
	UPDATE       OSFA_DB.dbo.OT_SystemOptions
	SET                Op_Value = @UseRangePrice
	WHERE        (CompNo = @CompNo) AND (Op_ID = 100) AND (SalesmanNo = 0)
END

End
--//////////////////////////////////////////////////////////////////////////////////////

INSERT INTO WF_PositionsVer (CompanyID, PositionID, WFVer)
SELECT        CompanyID, ID, 1 AS Expr1
FROM            Positions
WHERE        (CompanyID = @CompNo) AND (ID NOT IN (SELECT PositionID FROM WF_PositionsVer WHERE CompanyID = @CompNo))


INSERT INTO OSFA_DB.dbo.OT_Reasons (CompNo,[SalesmanNo], TypeCode, ReasonID, ArDesc, EnDesc,IsNeedNote)
SELECT        CompanyID, @SalesmanNo,ISNULL(ReasonType,1), ID, Name, Reference1,IsNeedNote
FROM            NoTransactionsReasons
WHERE        (CompanyID = @CompNo)  AND (ISNULL(ReasonType,1) < 999)

IF @ClientActive = 27
BEGIN
	
DELETE FROM [OSFA_DB].[dbo].[OT_Reasons] WHERE [CompNo] = @CompNo AND [SalesmanNo]=@SalesmanNo

	INSERT INTO OSFA_DB.dbo.OT_Reasons (CompNo,[SalesmanNo], TypeCode, ReasonID, ArDesc, EnDesc,IsNeedNote)
	SELECT        CompanyID, @SalesmanNo,99, Reference1, Name, ID,IsNeedNote
	FROM            NoTransactionsReasons
	WHERE        (CompanyID = @CompNo) AND (ISNULL(ReasonType,1) = @SalesmanNo) and ReasonType <> 100

		INSERT INTO OSFA_DB.dbo.OT_Reasons (CompNo,[SalesmanNo], TypeCode, ReasonID, ArDesc, EnDesc,IsNeedNote)
	SELECT      distinct  CompanyID, @SalesmanNo,100, NoTransactionsReasons.id, Name, name,IsNeedNote
	FROM            NoTransactionsReasons inner join OSFA_DB..OT_LinkedSalesman as LinkedSalesman on NoTransactionsReasons.CompanyID = LinkedSalesman.CompNo and NoTransactionsReasons.ID = LinkedSalesman.LinkedSalesmanNo
	WHERE        (CompanyID = @CompNo) AND (ReasonType) = 100 and LinkedSalesman.SalesmanNo =@SalesmanNo
	END

IF @ClientActive = 5
BEGIN
	INSERT INTO OSFA_DB.dbo.OT_Reasons (CompNo,[SalesmanNo], TypeCode, ReasonID, ArDesc, EnDesc,IsNeedNote)
	SELECT        CompanyID, @SalesmanNo,99, ID, Name, ID,IsNeedNote
	FROM            NoTransactionsReasons
	WHERE        (CompanyID = @CompNo) AND (ReasonType = 6)
END


INSERT INTO OSFA_DB.dbo.OT_ReprintReasons (CompNo,[SalesmanNo], ID, Name, EngName)
SELECT        CompanyID, @SalesmanNo,ID, Name, Name
FROM            ReprintReasons
WHERE        (CompanyID = @CompNo)


---END Send Company Data------------------------------------------------------------------------------
/*
SET @BeginTime = Convert(varchar(20),GetDate(),108)

if @SerialType = 1 --Serial By Notebooks
BEGIN
INSERT INTO [OSFA_DB].[dbo].[OT_SalesmanMF]
           ([CompNo]
           ,[SalesmanNo]
           ,[ArbSalesmanName]
           ,[EngSalesmanName]
           ,[Password]
           ,[Active]
           ,[NextSerial]
           ,[InvNextSerial]
           ,[RetInvNextSerial]
           ,[RecNextSerial]
           ,[StoreNo]
           ,[UseDefaultUnit]
           ,[AllowChangePrice]
           ,[AllowSales]
           ,[AllowReturnSales]
           ,[AllowOrder]
           ,[AllowRec]
           ,[AllowCons]
           ,[ConsNextSerial]
           ,[SalesmanGroup_ID]
           ,[AllowCustStock]
           ,[CustStockNextSerial]
           ,[AllowChangeOrderStore]
           ,[AllowChangeOrderBusUnit]
           ,[AllowChangeOrderDocType]
           ,[AllowChangeOrderCustName]
           ,[AllowMakeBonus]
           ,[AllowAddCust]
           ,[AllowGetCustGPS]
           ,[AllowItemDisc]
           ,[AllowVouDisc]
           ,[UseMultiStoreInSales]
           ,[AllowedVoidInvCount]
           ,[DayOff]
          ,[VouDiscLimit]
          ,[MinTotalOfSalesVou]
		  ,[CheckCreditLimitInOrder]
		  ,[CompetitiveItemsInfoNextSerial]
		  ,[SupervisorNo]
		  ,[SupervisorName]
		  ,[SupervisorTel]
		  ,[CompanyBrancheID]
		  ,[UnLoadOrdersNextSerials]
		  ,[CreditLimit]
		  ,[SalesmanBalance]
		  ,[AllowAddDrawer]
		  ,[MaxDiscountPerc]
		  ,[SalesmanStockNextSerial]
		  ,[AllowReturnOrder]
		  ,[ReturnOrderNextSerial]
		  ,[VanTransferNextSerial]
		  ,AllowVanTransfer
		  ,AutoSendData
		  ,AllowSalesQuotation 
		  ,SalesQuotationNextSerial
		  ,AllowItemsReplacment
		  ,ItemsReplacmentNextSerial
		  ,UserName
		  ,AllowAddProspectiveCust
		  ,SalesmanTel
		  ,AllowChangePriceInReturn
			, AllowItemDiscInReturn 
			,AllowVouDiscInReturn 
			,AllowUnloadOrder)
			SELECT        SalesPersons.CompanyID, SalesPersons.ID, SalesPersons.Name, SalesPersons.Name AS Eng, SalesPersonsDevicePermissions.Password, 1 AS Active, SalesPersonTransactionsSerials.OrderTakingNextSerial, 
									 SalesPersonTransactionsSerials.SalesInvoiceNextSerial, SalesPersonTransactionsSerials.ReturnSalesNextSerial, SalesPersonTransactionsSerials.ReceiptNextSerial, SalesPersons.ID AS Store, 
									 SalesPersonsDevicePermissions.UseDefaultUnit, SalesPersonsDevicePermissions.ChangePrice, SalesPersonsDevicePermissions.MakeSalesInvoice, SalesPersonsDevicePermissions.MakeReturnSales, 
									 SalesPersonsDevicePermissions.MakeOrderTaking, SalesPersonsDevicePermissions.MakeReceipt, SalesPersonsDevicePermissions.MakeTransferOrder, 
									 SalesPersonTransactionsSerials.TransferOrderNextSerial, SalesPersons.GroupID AS SalesmanGroup_ID, SalesPersonsDevicePermissions.AllowCustStock, SalesPersonTransactionsSerials.CustStockNextSerial, 
									 SalesPersonsDevicePermissions.AllowChangeOrderStore, SalesPersonsDevicePermissions.AllowChangeOrderBusUnit, SalesPersonsDevicePermissions.AllowChangeOrderDocType, 
									 SalesPersonsDevicePermissions.AllowChangeOrderCustName, SalesPersonsDevicePermissions.AllowMakeBonus, SalesPersonsDevicePermissions.AllowAddCust, 
									 SalesPersonsDevicePermissions.AllowGetCustGPS, SalesPersonsDevicePermissions.AllowItemDisc, SalesPersonsDevicePermissions.AllowVouDisc, SalesPersonsDevicePermissions.UseMultiStoreInSales, 
									 SalesPersonsDevicePermissions.CanceledInvoiceNo, ISNULL(SalesPersons.DayOff, 0) AS Expr1, SalesPersonsDevicePermissions.VouDiscLimit, SalesPersonsDevicePermissions.MinTotalOfSalesVou, 
									 SalesPersonsDevicePermissions.CheckCreditLimitInOrder, SalesPersonTransactionsSerials.CompetitiveItemsInfoNextSerial, @SupervisorNo AS Expr2, @SupervisorName AS Expr3, @SupervisorTel AS Expr4, 
									 SalesPersons.CompanyBrancheID, SalesPersonTransactionsSerials.UnLoadOrdersNextSerials, SalesPersons.CreditLimit, 0 AS SalesmanBalance, SalesPersonsDevicePermissions.AllowAddDrawer, 
									 SalesPersonsDevicePermissions.MaxDiscountPerc, SalesPersonTransactionsSerials.SalesmanStockNextSerial, SalesPersonsDevicePermissions.AllowReturnOrder, 
									 SalesPersonTransactionsSerials.ReturnOrderNextSerial, ISNULL(SalesPersonTransactionsSerials.VanTransferNextSerial, 0) AS Expr5, ISNULL(SalesPersonsDevicePermissions.AllowVanTransfer, 0) AS Expr6, 
									 ISNULL(SalesPersons.AutoSendData, 0) AS Expr7, ISNULL(SalesPersonsDevicePermissions.AllowSalesQuotation, 0) AS AllowSalesQuotation, ISNULL(SalesPersonTransactionsSerials.SalesQuotationNextSerial, 
									 0) AS SalesQuotationNextSerial, ISNULL(SalesPersonsDevicePermissions.AllowItemsReplacement, 0) AS AllowItemsReplacment, ISNULL(SalesPersonTransactionsSerials.ItemsReplacementNextSerial, 0) 
									 AS ItemsReplacmentNextSerial, SalespersonsSecurity.UserID, SalesPersonsDevicePermissions.AllowAddProspectiveCustomer, SalesPersons.TelephoneNo,ISNULL(AllowChangePriceInReturn,0) AS AllowChangePriceInReturn, AllowItemDiscInReturn ,AllowVouDiscInReturn,AllowUnloadOrder
			FROM            SalesPersons INNER JOIN						
									 SalesPersonsGroups ON SalesPersons.GroupID = SalesPersonsGroups.ID AND SalesPersons.CompanyID = SalesPersonsGroups.CompanyID INNER JOIN
									 SalesPersonsDevicePermissions ON SalesPersons.CompanyID = SalesPersonsDevicePermissions.CompanyID AND SalesPersons.PositionID = SalesPersonsDevicePermissions.PositionsID LEFT OUTER JOIN
									 SalespersonsSecurity ON SalesPersons.CompanyID = SalespersonsSecurity.CompanyID AND SalesPersons.ID = SalespersonsSecurity.SalespersonID LEFT OUTER JOIN
									 SalesPersonTransactionsSerials ON SalesPersons.CompanyID = SalesPersonTransactionsSerials.CompanyID AND SalesPersons.ID = SalesPersonTransactionsSerials.SalesPersonID
			WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo) AND (SalesPersonTransactionsSerials.SerYear = YEAR(@SendDate))
END 
ELSE
BEGIN
-- Serial By Salesman
INSERT INTO [OSFA_DB].[dbo].[OT_SalesmanMF] 
           ([CompNo]
           ,[SalesmanNo]
           ,[ArbSalesmanName]
           ,[EngSalesmanName]
           ,[Password]
           ,[Active]
           ,[NextSerial]
           ,[InvNextSerial]
           ,[RetInvNextSerial]
           ,[RecNextSerial]
           ,[StoreNo]
           ,[UseDefaultUnit]
           ,[AllowChangePrice]
           ,[AllowSales]
           ,[AllowReturnSales]
           ,[AllowOrder]
           ,[AllowRec]
           ,[AllowCons]
           ,[ConsNextSerial]
           ,[SalesmanGroup_ID]
           ,[AllowCustStock]
           ,[CustStockNextSerial]
           ,[AllowChangeOrderStore]
           ,[AllowChangeOrderBusUnit]
           ,[AllowChangeOrderDocType]
           ,[AllowChangeOrderCustName]
           ,[AllowMakeBonus]
           ,[AllowAddCust]
           ,[AllowGetCustGPS]
           ,[AllowItemDisc]
           ,[AllowVouDisc]
           ,[UseMultiStoreInSales]
           ,[AllowedVoidInvCount]
           ,[DayOff]
          ,[VouDiscLimit]
          ,[MinTotalOfSalesVou]
		  ,[CheckCreditLimitInOrder]
		  ,[CompetitiveItemsInfoNextSerial]
		  ,[SupervisorNo]
		  ,[SupervisorName]
		  ,[SupervisorTel]
		  ,[CompanyBrancheID]
		  ,[UnLoadOrdersNextSerials]
		  ,[CreditLimit]
		  ,[SalesmanBalance]
		  ,[AllowAddDrawer]
		  ,[MaxDiscountPerc]
		  ,[SalesmanStockNextSerial]
		  ,[AllowReturnOrder]
		  ,[ReturnOrderNextSerial]
		  ,[VanTransferNextSerial]
		  ,AllowVanTransfer
		  ,AutoSendData
		  ,AllowSalesQuotation
		  ,SalesQuotationNextSerial
		  ,AllowItemsReplacment
		  ,ItemsReplacmentNextSerial
		  ,UserName
		  ,AllowAddProspectiveCust
		  ,SalesmanTel
		  ,AllowChangePriceInReturn
			, AllowItemDiscInReturn 
			,AllowVouDiscInReturn
			,AllowUnloadOrder)
			SELECT        SalesPersons.CompanyID, SalesPersons.ID, SalesPersons.Name, (CASE WHEN @ClientActive = 19 THEN SalesPersons.Reference1 ELSE SalesPersons.Name END) AS Eng, 
									 SalesPersonsDevicePermissions.Password, 1 AS Active, SalesPersonTransactionsSerials.OrderTakingNextSerial, SalesPersonTransactionsSerials.SalesInvoiceNextSerial, 
									 SalesPersonTransactionsSerials.ReturnSalesNextSerial, SalesPersonTransactionsSerials.ReceiptNextSerial, SalesPersons.ID AS Store, SalesPersonsDevicePermissions.UseDefaultUnit, 
									 SalesPersonsDevicePermissions.ChangePrice, SalesPersonsDevicePermissions.MakeSalesInvoice, SalesPersonsDevicePermissions.MakeReturnSales, SalesPersonsDevicePermissions.MakeOrderTaking, 
									 SalesPersonsDevicePermissions.MakeReceipt, SalesPersonsDevicePermissions.MakeTransferOrder, SalesPersonTransactionsSerials.TransferOrderNextSerial, SalesPersons.GroupID AS SalesmanGroup_ID, 
									 SalesPersonsDevicePermissions.AllowCustStock, SalesPersonTransactionsSerials.CustStockNextSerial, SalesPersonsDevicePermissions.AllowChangeOrderStore, 
									 SalesPersonsDevicePermissions.AllowChangeOrderBusUnit, SalesPersonsDevicePermissions.AllowChangeOrderDocType, SalesPersonsDevicePermissions.AllowChangeOrderCustName, 
									 SalesPersonsDevicePermissions.AllowMakeBonus, SalesPersonsDevicePermissions.AllowAddCust, SalesPersonsDevicePermissions.AllowGetCustGPS, SalesPersonsDevicePermissions.AllowItemDisc, 
									 SalesPersonsDevicePermissions.AllowVouDisc, SalesPersonsDevicePermissions.UseMultiStoreInSales, SalesPersonsDevicePermissions.CanceledInvoiceNo, ISNULL(SalesPersons.DayOff, 0) AS Expr1, 
									 SalesPersonsDevicePermissions.VouDiscLimit, SalesPersonsDevicePermissions.MinTotalOfSalesVou, SalesPersonsDevicePermissions.CheckCreditLimitInOrder, 
									 SalesPersonTransactionsSerials.CompetitiveItemsInfoNextSerial, @SupervisorNo AS Expr2, @SupervisorName AS Expr3, @SupervisorTel AS Expr4, SalesPersons.CompanyBrancheID, 
									 SalesPersonTransactionsSerials.UnLoadOrdersNextSerials, SalesPersons.CreditLimit, 0 AS SalesmanBalance, SalesPersonsDevicePermissions.AllowAddDrawer, 
									 SalesPersonsDevicePermissions.MaxDiscountPerc, SalesPersonTransactionsSerials.SalesmanStockNextSerial, SalesPersonsDevicePermissions.AllowReturnOrder, 
									 SalesPersonTransactionsSerials.ReturnOrderNextSerial, ISNULL(SalesPersonTransactionsSerials.VanTransferNextSerial, 0) AS Expr5, ISNULL(SalesPersonsDevicePermissions.AllowVanTransfer, 0) AS Expr6, 
									 ISNULL(SalesPersons.AutoSendData, 0) AS Expr7, ISNULL(SalesPersonsDevicePermissions.AllowSalesQuotation, 0) AS AllowSalesQuotation, ISNULL(SalesPersonTransactionsSerials.SalesQuotationNextSerial, 
									 0) AS SalesQuotationNextSerial, ISNULL(SalesPersonsDevicePermissions.AllowItemsReplacement, 0) AS AllowItemsReplacment, ISNULL(SalesPersonTransactionsSerials.ItemsReplacementNextSerial, 0) 
									 AS ItemsReplacmentNextSerial, SalespersonsSecurity.UserID, SalesPersonsDevicePermissions.AllowAddProspectiveCustomer, SalesPersons.TelephoneNo,ISNULL(AllowChangePriceInReturn,0) AS AllowChangePriceInReturn, AllowItemDiscInReturn ,AllowVouDiscInReturn,AllowUnloadOrder
			FROM            SalesPersons INNER JOIN
									 SalesPersonTransactionsSerials ON SalesPersons.CompanyID = SalesPersonTransactionsSerials.CompanyID AND SalesPersons.ID = SalesPersonTransactionsSerials.SalesPersonID INNER JOIN
									 SalesPersonsGroups ON SalesPersons.GroupID = SalesPersonsGroups.ID AND SalesPersons.CompanyID = SalesPersonsGroups.CompanyID INNER JOIN
									 SalesPersonsDevicePermissions ON SalesPersons.CompanyID = SalesPersonsDevicePermissions.CompanyID AND SalesPersons.PositionID = SalesPersonsDevicePermissions.PositionsID LEFT OUTER JOIN
									 SalespersonsSecurity ON SalesPersons.CompanyID = SalespersonsSecurity.CompanyID AND SalesPersons.ID = SalespersonsSecurity.SalespersonID
			WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo) AND (SalesPersonTransactionsSerials.SerYear = YEAR(@SendDate))


END

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_SalesmanMF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
*/

--///////////// System Options /////////////////////////////////////////////
INSERT INTO [OSFA_DB].[dbo].[OT_SystemOptions]
                      (CompNo, Op_ID, SalesmanNo, Op_Desc, Op_Value, Notes)
SELECT     CompNo, Op_ID, @SalesmanNo, Op_Desc, (SELECT CASE WHEN [UseBarcodeForCustLogin]<>0 THEN 1 ELSE 0 END FROM [SalesPersonsDevicePermissions] WHERE CompanyID=@CompNo AND PositionsID=@PositionsID), Notes
FROM         [OSFA_DB].[dbo].[OT_SystemOptions]          
WHERE [CompNo]=@CompNo AND [SalesmanNo]=0 AND Op_ID=1

INSERT INTO [OSFA_DB].[dbo].[OT_SystemOptions]
                      (CompNo, Op_ID, SalesmanNo, Op_Desc, Op_Value, Notes)
SELECT     CompNo, Op_ID, @SalesmanNo, Op_Desc, (SELECT IsNull([AmendChangeCashCreditInInvoice],0) FROM [SalesPersonsDevicePermissions] WHERE CompanyID=@CompNo AND PositionsID=@PositionsID), Notes
FROM         [OSFA_DB].[dbo].[OT_SystemOptions]          
WHERE [CompNo]=@CompNo AND [SalesmanNo]=0 AND Op_ID=31

INSERT INTO [OSFA_DB].[dbo].[OT_SystemOptions]
                      (CompNo, Op_ID, SalesmanNo, Op_Desc, Op_Value, Notes)
SELECT     CompNo, Op_ID, @SalesmanNo, Op_Desc, (SELECT IsNull([AmendChangeCashCreditInRetInvoice],0) FROM [SalesPersonsDevicePermissions] WHERE CompanyID=@CompNo AND PositionsID=@PositionsID), Notes
FROM         [OSFA_DB].[dbo].[OT_SystemOptions]          
WHERE [CompNo]=@CompNo AND [SalesmanNo]=0 AND Op_ID=32

INSERT INTO [OSFA_DB].[dbo].[OT_SystemOptions]
                      (CompNo, Op_ID, SalesmanNo, Op_Desc, Op_Value, Notes)
SELECT     CompNo, Op_ID, @SalesmanNo, Op_Desc, (SELECT IsNull([CashOnlyInvoice],0) FROM [SalesPersonsDevicePermissions] WHERE CompanyID=@CompNo AND PositionsID=@PositionsID), Notes
FROM         [OSFA_DB].[dbo].[OT_SystemOptions]          
WHERE [CompNo]=@CompNo AND [SalesmanNo]=0 AND Op_ID=33

INSERT INTO [OSFA_DB].[dbo].[OT_SystemOptions]
                      (CompNo, Op_ID, SalesmanNo, Op_Desc, Op_Value, Notes)
SELECT     CompNo, Op_ID, @SalesmanNo, Op_Desc, (SELECT IsNull([CreditOnlyReturnInvoice],0) FROM [SalesPersonsDevicePermissions] WHERE CompanyID=@CompNo AND PositionsID=@PositionsID), Notes
FROM         [OSFA_DB].[dbo].[OT_SystemOptions]          
WHERE [CompNo]=@CompNo AND [SalesmanNo]=0 AND Op_ID=34

INSERT INTO [OSFA_DB].[dbo].[OT_SystemOptions]
                      (CompNo, Op_ID, SalesmanNo, Op_Desc, Op_Value, Notes)
SELECT     CompNo, Op_ID, @SalesmanNo, Op_Desc, (SELECT IsNull(AllowCompetitiveItems,0) FROM [SalesPersonsDevicePermissions] WHERE CompanyID=@CompNo AND PositionsID=@PositionsID), Notes
FROM         [OSFA_DB].[dbo].[OT_SystemOptions]          
WHERE [CompNo]=@CompNo AND [SalesmanNo]=0 AND Op_ID=39
------------------------------------------

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_CompanyBranches, OT_SystemOptions, OT_Reasons, OT_ReprintReasons, WF_PositionsVer [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

--///// Get Items Info //////////////////////////////////

SET @BeginTime = Convert(varchar(20),GetDate(),108)

EXEC dbo.OT_SendItemsInfo @CompNo,@ClientActive,@SalesmanNo,@PositionsID
if @ClientActive=152
Begin
Declare @makeorder bit =(select MakeOrderTaking from salespersonsdevicepermissions where CompanyID=@CompNo and PositionsID=@PositionsID)
if @makeorder=1
Begin
UPDATE       OSFA_DB.dbo.OT_ItemsMF
SET                QtyOH =Qty
FROM            OSFA_DB.dbo.OT_StoreItemsQty_Main INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON OSFA_DB.dbo.OT_StoreItemsQty_Main.CompNo = OSFA_DB.dbo.OT_ItemsMF.CompNo AND OSFA_DB.dbo.OT_StoreItemsQty_Main.SalesmanNo = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
                         OSFA_DB.dbo.OT_StoreItemsQty_Main.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo
WHERE        (OSFA_DB.dbo.OT_StoreItemsQty_Main.StoreNo = 999999)
END

END
IF @ClientActive <> 24 AND @ClientActive <> 42 AND @ClientActive <> 11 AND @ClientActive <> 27 AND @ClientActive <> 59 AND @ClientActive <>55 AND @ClientActive <>85 AND @ClientActive <>51
AND @ClientActive <>35 and @ClientActive <> 5  and @ClientActive <> 95
BEGIN

select 0 
/*
Declare @ItemCount int
SET @ItemCount = 0
SELECT @ItemCount = COUNT(*) FROM OSFA_DB.dbo.OT_ItemsMF WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (Unit1 <> Unit2) AND (Conv1 = 1)
IF @ItemCount <> 0
BEGIN
	goto EXITPRO
END

SET @ItemCount = 0
SELECT @ItemCount = COUNT(*) FROM OSFA_DB.dbo.OT_ItemsMF WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (Unit2 <> Unit3) AND (Conv2 = 1)
IF @ItemCount <> 0
BEGIN
	goto EXITPRO
END

SET @ItemCount = 0
SELECT @ItemCount = COUNT(*) FROM OSFA_DB.dbo.OT_ItemsMF WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (Unit3 <> Unit4) AND (Conv3 = 1)
IF @ItemCount <> 0
BEGIN
	goto EXITPRO
END
*/
END

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_ItemsMF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
print'ad'


IF @ClientActive=123 -----Chains  
BEGIN

IF @IsMakeOrder =1
BEGIN 
delete  from OSFA_DB.DBO.OT_StoreItemsQty where CompNo=@CompNo and  StoreNo=@SalesmanNo  
INSERT INTO OSFA_DB.DBO.OT_StoreItemsQty
                         (CompNo,  StoreNo, ItemNo, Qty)

select @CompNo, @SalesmanNo,ItemCode,100 from Olives_BO..Items where CompanyID=@CompNo
--and StoreNo='01'  


UPDATE OSFA_DB.dbo.OT_ItemsMF
SET          QtyOH=100
FROM     StoresBalances INNER JOIN
                  OSFA_DB.dbo.OT_ItemsMF ON StoresBalances.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo
				  AND StoresBalances.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
where CompanyID=@CompNo and SalesmanNo=@SalesmanNo and StoresBalances.StoreNo='01'


END 

END
	
IF @ClientActive=110
BEGIN
Select  'Azoqa'
delete from OSFA_DB.dbo.OT_StoreItemsQty_Main where CompNo=@CompNo and SalesmanNo=@SalesmanNo
INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty_Main
                         (CompNo, SalesmanNo,ItemNo, Qty,StoreNo)


SELECT     distinct    OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, [dbo].[GetItemSmallUnitQty] (1 , OSFA_DB.dbo.OT_ItemsMF.ItemNo ,1 ,ISNULL(StoresBalances.Qty, 0)  )  AS Expr2, 999999 AS Expr1
FROM            OSFA_DB.dbo.OT_ItemsMF LEFT OUTER JOIN
                         StoresBalances ON OSFA_DB.dbo.OT_ItemsMF.CompNo = StoresBalances.CompanyID AND OSFA_DB.dbo.OT_ItemsMF.ItemNo = StoresBalances.ItemCode
						  AND (StoresBalances.StoreNo = '08')
WHERE        (OSFA_DB.dbo.OT_ItemsMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo) 


END 







if @ClientActive=64
Begin

UPDATE    OSFA_DB.dbo.OT_ItemsMF
SET          OSFA_DB.dbo.OT_ItemsMF.QtyOH =DB.dbo.InvBatchsMF.QtyOH
FROM        DB.dbo.InvBatchsMF INNER JOIN
                  OSFA_DB.dbo.OT_ItemsMF ON DB.dbo.InvBatchsMF.CompNo = OSFA_DB.dbo.OT_ItemsMF.CompNo AND DB.dbo.InvBatchsMF.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo
WHERE     (DB.dbo.InvBatchsMF.CompNo = @CompNo) AND (DB.dbo.InvBatchsMF.IsHalt = 0) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo) AND (DB.dbo.InvBatchsMF.StoreNo IN (1))


End


--//////////// Update Item Promotion  //////////////////////////////////////////
/*
UPDATE       OSFA_DB.dbo.OT_PromotionsCondUnCodInput
SET                ItemNo =
                             (SELECT        TOP (1) ItemNo
                                FROM            OSFA_DB.dbo.OT_ItemsMF
                                WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (NOT (ItemNo IN
                                                             (SELECT        ItemNo
                                                                FROM            OSFA_DB.dbo.OT_PromotionsCondUnCodInput AS OT_PromotionsCondUnCodInput_1
                                                                WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)))))
FROM            OSFA_DB.dbo.OT_PromotionsCondUnCodInput INNER JOIN
                         OSFA_DB.dbo.OT_PromotionsHeaders ON OSFA_DB.dbo.OT_PromotionsCondUnCodInput.CompNo = OSFA_DB.dbo.OT_PromotionsHeaders.CompNo AND 
                         OSFA_DB.dbo.OT_PromotionsCondUnCodInput.SalesmanNo = OSFA_DB.dbo.OT_PromotionsHeaders.SalesmanNo AND 
                         OSFA_DB.dbo.OT_PromotionsCondUnCodInput.PromotionCode = OSFA_DB.dbo.OT_PromotionsHeaders.PromotionCode
WHERE        (OSFA_DB.dbo.OT_PromotionsCondUnCodInput.CompNo = @CompNo) AND (ISNULL(OSFA_DB.dbo.OT_PromotionsCondUnCodInput.InputType, 0) = 1) AND 
                         (OSFA_DB.dbo.OT_PromotionsCondUnCodInput.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_PromotionsHeaders.PromotionType IN (12, 14))
						 */

/*
SET @BeginTime = Convert(varchar(20),GetDate(),108)

SELECT        TOP (1) ItemNo
FROM            OSFA_DB.dbo.OT_ItemsMF
WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
IF @@RowCount <> 0
BEGIN
	UPDATE       OSFA_DB.dbo.OT_PromotionsCondUnCodOutput
	SET                ItemNo =
								 (SELECT        TOP (1) ItemNo
									FROM            OSFA_DB.dbo.OT_ItemsMF
									WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)/* AND (NOT (ItemNo IN
																 (SELECT        ItemNo
																	FROM            OSFA_DB.dbo.OT_PromotionsCondUnCodOutput AS OT_PromotionsCondUnCodOutput_1
																	WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo))))*/ )
	FROM            OSFA_DB.dbo.OT_PromotionsCondUnCodOutput INNER JOIN
							 OSFA_DB.dbo.OT_PromotionsHeaders ON OSFA_DB.dbo.OT_PromotionsCondUnCodOutput.CompNo = OSFA_DB.dbo.OT_PromotionsHeaders.CompNo AND 
							 OSFA_DB.dbo.OT_PromotionsCondUnCodOutput.SalesmanNo = OSFA_DB.dbo.OT_PromotionsHeaders.SalesmanNo AND 
							 OSFA_DB.dbo.OT_PromotionsCondUnCodOutput.PromotionCode = OSFA_DB.dbo.OT_PromotionsHeaders.PromotionCode
	WHERE        (OSFA_DB.dbo.OT_PromotionsCondUnCodOutput.CompNo = @CompNo) AND (ISNULL(OSFA_DB.dbo.OT_PromotionsCondUnCodOutput.OutPutType, 1) = 0) AND 
							 (OSFA_DB.dbo.OT_PromotionsCondUnCodOutput.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_PromotionsHeaders.PromotionType IN (12, 14))
END

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Update OT_PromotionsCondUnCodOutput From OT_ItemsMF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
*/
--//////////////////////////////////////////////////////////////////////////
/*
	DECLARE @cItemNo varchar(100)
	DECLARE @i bigint
	SET @i = 1
	
	DECLARE Items CURSOR FOR

		SELECT ItemNo FROM [OSFA_DB].[dbo].[OT_ItemsMF] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)

	OPEN Items
		FETCH NEXT FROM Items
		INTO @cItemNo
			WHILE @@FETCH_STATUS = 0
			BEGIN
			 
				UPDATE [OSFA_DB].[dbo].[OT_ItemsMF] SET ImageID = @i
				WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (ItemNo = @cItemNo)
			
				SET @i = @i + 1
				
				FETCH NEXT FROM Items
				INTO @cItemNo
			END
	CLOSE Items
	DEALLOCATE Items 
	*/






	-- ///////// Receipt Requests ////////////////////

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	IF @ClientActive = 62
	Begin
	INSERT INTO [OSFA_DB].[dbo].[OT_ReceiptRequests]
			   ([CompanyID]
			   ,[OrderYear]
			   ,[OrderNo]
			   ,[SalesmanNo]
			   ,[OrderDate]
			   ,[CustomerID]
			   ,[Amount]
			   ,[Notes]
			   ,[OrderStatus]
			   ,[PaymentType]
			   ,[IsSettlement]
			   ,[Priority]
			   ,DocType)

			   /*
	SELECT        ReceiptRequests.CompanyID, ReceiptRequests.OrderYear, ReceiptRequests.OrderNo, ReceiptRequestsSchedule.SalesPersonID, ReceiptRequests.OrderDate, ReceiptRequests.CustomerID, round ( ReceiptRequests.Amount,3), ReceiptRequests.Notes, 
							 ReceiptRequests.OrderStatus, ReceiptRequests.PaymentType, ReceiptRequests.IsSettlement, ReceiptRequests.Priority,ReceiptRequests.DocumentTypeID
	FROM            ReceiptRequests INNER JOIN
							 ReceiptRequestsSchedule ON ReceiptRequests.CompanyID = ReceiptRequestsSchedule.CompanyID AND ReceiptRequests.OrderYear = ReceiptRequestsSchedule.OrderYear AND 
							 ReceiptRequests.OrderNo = ReceiptRequestsSchedule.OrderNo
	WHERE        (ISNULL(ReceiptRequests.OrderStatus,0) IN (0,1)) AND (ReceiptRequests.CompanyID = @CompNo) AND (ReceiptRequestsSchedule.SalesPersonID = @SalesmanNo) AND (ISNULL(ReceiptRequestsSchedule.IsVoid,0) = 0)
	
*/
	SELECT        ReceiptRequests.CompanyID, ReceiptRequests.OrderYear, ReceiptRequests.OrderNo, ReceiptRequestsSchedule.SalesPersonID, ReceiptRequests.OrderDate, ReceiptRequests.CustomerID, 
                         CASE WHEN ReceiptRequests.DocumentTypeID = 1 THEN round(ReceiptRequests.Amount, 3) ELSE round(ReceiptRequests.Amount, 2) END AS Expr1, ReceiptRequests.Notes, ReceiptRequests.OrderStatus, 
                         ReceiptRequests.PaymentType, ReceiptRequests.IsSettlement, ReceiptRequests.Priority, ReceiptRequests.DocumentTypeID
FROM            ReceiptRequests INNER JOIN
                         ReceiptRequestsSchedule ON ReceiptRequests.CompanyID = ReceiptRequestsSchedule.CompanyID AND ReceiptRequests.OrderYear = ReceiptRequestsSchedule.OrderYear AND 
                         ReceiptRequests.OrderNo = ReceiptRequestsSchedule.OrderNo LEFT OUTER JOIN
                         OSFA_DB.dbo.OT_Payments ON ReceiptRequests.CompanyID = OSFA_DB.dbo.OT_Payments.CompNo AND ReceiptRequests.OrderYear = OSFA_DB.dbo.OT_Payments.RequestOrderYear AND 
                         ReceiptRequests.OrderNo = OSFA_DB.dbo.OT_Payments.RequestOrderNo
WHERE        (ISNULL(ReceiptRequests.OrderStatus, 0) IN (0, 1)) AND (ReceiptRequests.CompanyID = @CompNo) AND (ReceiptRequestsSchedule.SalesPersonID = @SalesmanNo) AND 
                         (ISNULL(ReceiptRequestsSchedule.IsVoid, 0) = 0) AND (OSFA_DB.dbo.OT_Payments.CompNo IS NULL)

	End

	else

	Begin
	INSERT INTO [OSFA_DB].[dbo].[OT_ReceiptRequests]
			   ([CompanyID]
			   ,[OrderYear]
			   ,[OrderNo]
			   ,[SalesmanNo]
			   ,[OrderDate]
			   ,[CustomerID]
			   ,[Amount]
			   ,[Notes]
			   ,[OrderStatus]
			   ,[PaymentType]
			   ,[IsSettlement]
			   ,[Priority]
			   ,DocType)
	SELECT        ReceiptRequests.CompanyID, ReceiptRequests.OrderYear, ReceiptRequests.OrderNo, ReceiptRequestsSchedule.SalesPersonID, ReceiptRequests.OrderDate, ReceiptRequests.CustomerID, round ( ReceiptRequests.Amount,3), ReceiptRequests.Notes, 
							 ReceiptRequests.OrderStatus, ReceiptRequests.PaymentType, ReceiptRequests.IsSettlement, ReceiptRequests.Priority,ReceiptRequests.DocumentTypeID
	FROM            ReceiptRequests INNER JOIN
							 ReceiptRequestsSchedule ON ReceiptRequests.CompanyID = ReceiptRequestsSchedule.CompanyID AND ReceiptRequests.OrderYear = ReceiptRequestsSchedule.OrderYear AND 
							 ReceiptRequests.OrderNo = ReceiptRequestsSchedule.OrderNo
	WHERE        (ISNULL(ReceiptRequests.OrderStatus,0) IN (0,1)) AND (ReceiptRequests.CompanyID = @CompNo) AND (ReceiptRequestsSchedule.SalesPersonID = @SalesmanNo) AND (ISNULL(ReceiptRequestsSchedule.IsVoid,0) = 0)

	End



	INSERT INTO [OSFA_DB].[dbo].[OT_ReceiptRequestsInvoicesLink]
			   ([CompanyID]
			   ,[OrderYear]
			   ,[OrderNo]
			   ,[PaidTransYear]
			   ,[PaidTransNo]
			   ,[PaidTransTypeID]
			   ,[SalesmanNo])
	SELECT        ReceiptRequestsInvoicesLink.CompanyID, ReceiptRequestsInvoicesLink.OrderYear, ReceiptRequestsInvoicesLink.OrderNo, ReceiptRequestsInvoicesLink.PaidTransYear, ReceiptRequestsInvoicesLink.PaidTransNo, 
							 ReceiptRequestsInvoicesLink.PaidTransTypeID,@SalesmanNo
	FROM            ReceiptRequests INNER JOIN
							 ReceiptRequestsSchedule ON ReceiptRequests.CompanyID = ReceiptRequestsSchedule.CompanyID AND ReceiptRequests.OrderYear = ReceiptRequestsSchedule.OrderYear AND 
							 ReceiptRequests.OrderNo = ReceiptRequestsSchedule.OrderNo INNER JOIN
							 ReceiptRequestsInvoicesLink ON ReceiptRequests.CompanyID = ReceiptRequestsInvoicesLink.CompanyID AND ReceiptRequests.OrderYear = ReceiptRequestsInvoicesLink.OrderYear AND 
							 ReceiptRequests.OrderNo = ReceiptRequestsInvoicesLink.OrderNo
	WHERE        (ISNULL(ReceiptRequests.OrderStatus,0) IN (0, 1)) AND (ReceiptRequests.CompanyID = @CompNo) AND (ReceiptRequestsSchedule.SalesPersonID = @SalesmanNo) AND (ISNULL(ReceiptRequestsSchedule.IsVoid, 0) = 0)

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_ReceiptRequests, OT_ReceiptRequestsInvoicesLink [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')


	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	if @ClientActive=27 and @CompNo=1 and  @PositionsID between 4000 and 4999
	begin
	    update CustomersFinancialDetails set PriceListID=4 where CustomerID=120411074681 and PositionsID=@PositionsID and CompanyID=@CompNo
	end 
If @ClientActive=13 and @CompNo=3 and @SalesmanGroupID=2
	begin
			UPDATE    CustomersFinancialDetails
			SET           PriceListID =4
			FROM        CustomersFinancialDetails 
			where PositionsID=@PositionsID and companyid=@CompNo 
    END

if @ClientActive = 122
Begin
update CustomersFinancialDetails set PriceListID=2 where PositionsID=2 and CompanyID=@CompNo
end



			If @ClientActive=13 and @CompNo=3 and @SalesmanNo=129 
	begin
			UPDATE    CustomersFinancialDetails
			SET           PriceListID =3
			FROM        CustomersFinancialDetails 
			where PositionsID=@PositionsID and companyid=@CompNo and customerid=28626
	END
	print 'OT_CustomerMF 2021'
		select @CompNo, @SendDate, @ClientActive, @SalesmanNo, @PositionsID, @OnlyCustomersOnRoutes, @SalesPersonType, @GroupCustByRelatedSalespersons,@SalesmanCarID
	EXEC dbo.OT_SendCustomersInfo @CompNo, @SendDate, @ClientActive, @SalesmanNo, @PositionsID, @OnlyCustomersOnRoutes, @SalesPersonType, @GroupCustByRelatedSalespersons,@SalesmanCarID
		print 'OT_CustomerMF 2022'

if @ClientActive=27 and @CompNo =1 and  @PositionsID between 8000 and 8999  --and @PositionsID<>8575
	Begin
	--Update CustomersFinancialDetails set PriceListID=401 where CompanyID=@CompNo and PositionsID = @PositionsID   and customerid=120411014840
	UPDATE       CustomersFinancialDetails
SET                PriceListID = 401
WHERE        (CompanyID = @CompNo) AND (PositionsID = @PositionsID) AND (CustomerID NOT IN (120411012847, 120411023941, 120411343513, 120411413018, 120411442935, 120411072318))
	Update CustomersFinancialDetails set PriceListID=325 where CompanyID=@CompNo and PositionsID = @PositionsID AND (CustomerID  IN (120411012847, 120411023941, 120411343513, 120411413018, 120411442935, 120411072318)) --and customerid<>120411014840
	End																		  
	   
if @ClientActive=27 and @compno=1 and @salesmanno  between 8000 and 8999
		begin
		update OSFA_DB..ot_customerMF set prno=401 where salesmanno =@SalesmanNo and compno=@CompNo and customerno=120411014840
		Update OSFA_DB..ot_customerMF set prno=323  where compno=@compno and customerno not in (120411014840,120411012847, 120411023941, 120411343513, 120411413018, 120411442935, 120411072318) and salesmanno =@SalesmanNo
	
		END																													 
																														   
 if @ClientActive=27 and @compno=2 and @salesmanno  in (8801,8820,8890,8805)
		begin
		update OSFA_DB..ot_customerMF set prno=401 where salesmanno =@SalesmanNo and compno=@CompNo and customerno=120411080184
		Update OSFA_DB..ot_customerMF set prno=323  where compno=@compno and customerno<>120411080184 and salesmanno =@SalesmanNo
		END
		If @ClientActive=27 and @CompNo=3 and @SalesmanNo in (8301,8303,8305,8307,8351,8352,8361,8370,8380,8390,8391)
		Begin
		update osfa_DB..OT_CustomerMF set prno=401 where customerno=120411030015 and salesmanno
		in(8301,8303,8305,8307,8351,8352,8361,8370,8380,8390,8391) and compno=@CompNo
        END
  
																			 
	   
																														 
																														   
	 
																											   
	   
																						 
																			   

																						  
																			   
	 

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_CustomerMF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')


	SET @BeginTime = Convert(varchar(20),GetDate(),108)


if @ClientActive = 30
BEGIN
	delete from SalesPersonItemsBalance where CompanyID=@Compno and SalesPersonID=@salesmanno	
	Exec Alpha_GetItemBalance_Zoumt @Compno,@salesmanno,@senddate 
END

if @ClientActive = 84
BEGIN
	delete from SalesPersonItemsBalance where CompanyID=@Compno and SalesPersonID=@salesmanno	
	Exec Alpha_GetItemBalance @Compno,@salesmanno,@senddate 
END
 if @ClientActive=122
begin
exec [dbo].[Boanza_Morek_GetitembalanceInsert] @CompNo,@SalesmanNo
end

if @ClientActive = 66
BEGIN
	delete from SalesPersonItemsBalance where CompanyID=@Compno and SalesPersonID=@salesmanno	
	Exec Alpha_GetItemBalance @Compno,@salesmanno,@senddate 
END

IF @ClientActive = 73
BEGIN
	EXEC Motakaml_Integ_GetItemBalance @CompNo,@SalesmanNo
END

IF @ClientActive = 139
BEGIN
	EXEC    [dbo].[Mira_Integ_GetItemBalance2022] @CompNo, @SalesmanNo
END
IF @ClientActive = 143
BEGIN
	EXEC    [dbo].[Mira_Integ_GetItemBalance] @CompNo, @SalesmanNo
END
--IF @ClientActive = 136 and @CompNo=1
--BEGIN
--	EXEC    [dbo].[ABS_Integ_GetItemBalance] @CompNo, @SalesmanNo
--END





if @ClientActive =92
Begin

	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])

select CompNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo,xbt.Quantity
FROM         (SELECT     Items.CompanyID, CitMultiStore.dbo.WHStock_V.StoreNo, CitMultiStore.dbo.WHStock_V.ItemNo, CitMultiStore.dbo.WHStock_V.Unit, 
                                              CitMultiStore.dbo.WHStock_V.Quantity
                        FROM         CitMultiStore.dbo.WHStock_V INNER JOIN
                                              Items ON CitMultiStore.dbo.WHStock_V.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS = Items.ItemCode AND 
                                              CitMultiStore.dbo.WHStock_V.Unit = Items.UnitID COLLATE Arabic_CI_AS
                        WHERE     (CitMultiStore.dbo.WHStock_V.StoreNo = 1) AND (Items.CompanyID = 1)) AS xbt INNER JOIN
                      OSFA_DB.dbo.OT_ItemsMF ON xbt.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
                      xbt.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS = OSFA_DB.dbo.OT_ItemsMF.ItemNo AND 
                      xbt.Unit = OSFA_DB.dbo.OT_ItemsMF.Unit1 COLLATE Arabic_CI_AS
                      where CompNo=@compno and OSFA_DB.dbo.OT_ItemsMF.SalesmanNo=@SalesmanNo

UPDATE    OSFA_DB.dbo.OT_ItemsMF
SET              QtyOH =xbt.Quantity
FROM         (SELECT     Items.CompanyID, CitMultiStore.dbo.WHStock_V.StoreNo, CitMultiStore.dbo.WHStock_V.ItemNo, CitMultiStore.dbo.WHStock_V.Unit, 
                                              CitMultiStore.dbo.WHStock_V.Quantity
                        FROM         CitMultiStore.dbo.WHStock_V INNER JOIN
                                              Items ON CitMultiStore.dbo.WHStock_V.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS = Items.ItemCode AND 
                                              CitMultiStore.dbo.WHStock_V.Unit = Items.UnitID COLLATE Arabic_CI_AS
                        WHERE     (CitMultiStore.dbo.WHStock_V.StoreNo = 1) AND (Items.CompanyID = @CompNo)) AS xbt INNER JOIN
                      OSFA_DB.dbo.OT_ItemsMF ON xbt.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
                      xbt.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS = OSFA_DB.dbo.OT_ItemsMF.ItemNo AND 
                      xbt.Unit = OSFA_DB.dbo.OT_ItemsMF.Unit1 COLLATE Arabic_CI_AS


End



--//// Hayat ////////////////////////////
if @ClientActive =111
Begin

Select @StoreNo = ForeignName from SalesPersons where CompanyID=@CompNo and ID = @SalesmanNo


	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])

select CompNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo,Sum (xbt.QTY )
FROM         (
					  SELECT     Items.CompanyID, ITEMSTOCKBALANCE.SITE, ITEMSTOCKBALANCE.ItemNo, 
                                             ITEMSTOCKBALANCE.QTY
                        FROM         X3IntegrationDB..ITEMSTOCKBALANCE As ITEMSTOCKBALANCE  INNER JOIN
                                              Items ON ITEMSTOCKBALANCE.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS = Items.ItemCode   
											    inner Join olives_bo.dbo.Fun_ConvArrayToTable (@StoreNo , ',') as i
							 on ITEMSTOCKBALANCE.SITE collate SQL_Latin1_General_CP1256_CI_AS  = i.stringPart
                        WHERE     (Items.CompanyID = @CompNo)) AS xbt INNER JOIN
                      OSFA_DB.dbo.OT_ItemsMF ON xbt.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
                      xbt.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS = OSFA_DB.dbo.OT_ItemsMF.ItemNo  
                      where CompNo=@compno and OSFA_DB.dbo.OT_ItemsMF.SalesmanNo=@SalesmanNo
					  Group by CompNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo



end

IF @ClientActive = 75
BEGIN
	EXEC SN_Integ_GetItemBalance @CompNo,@SalesmanNo
END

IF @ClientActive = 80
BEGIN
	EXEC SAP_GetItemBalance_Humoodoh @CompNo,@SalesmanNo
END

SET DATEFIRST 6;
declare @RouteID int
declare @WeekNo int
declare @DayOfWeek int

SET @WeekNo = dbo.Fun_GetWeekNo(@SendDate)
SET @DayOfWeek = DATEPART(dw, @SendDate)

---Additional Routes -------------------------------------------------------------------------------
print 'Hereee'

select @WeekNo,@DayOfWeek,@PositionsID
INSERT INTO [OSFA_DB].[dbo].[OT_CustomerMF]
           ([CompNo]
           ,[CustomerNo]
           ,[SalesmanNo]
           ,[ArName]
           ,[EngName]
           ,[PrNo]
           ,[CustType]
           ,[CustClass]
           ,[CreditLimit]
           ,[CurrBalance]
           ,[ChqsBalance]
           ,[GeoLevel1]
           ,[GeoLevel2]
           ,[GeoLevel3]
           ,[GeoLevel4]
           ,[GeoLevel5]
           ,[CustomerBarcode]
           ,[X_COORD]
           ,[Y_COORD]
           ,[PriceLevel]
           ,[Due]
           ,[ChqDue]
           ,[TaxInclude]
           ,[Tel]
           ,[Email]
           ,[CustomerRef1]
		   ,CustomerRef2
           ,[CreditCash]
		   ,[AllowChqs]		   
		   ,ImageID
		   ,IsSuspended
		   ,DiscountPerc
		   ,FullAddress
		   ,MaxInvoiceValue
		   ,MaxInvoiceCount
		   ,[ChqLimit]
		   ,Tax_1_Include
			,Tax_2_Include
		   ,ContactPerson
		   ,TaxNum
		   ,AllowDiscount)
SELECT DISTINCT Customers.CompanyID, Customers.ID, @SalesmanNo AS SalesmanNo, Customers.Name AS ar, Customers.Name AS en,
 CustomersFinancialDetails.PriceListID AS PrNo, Customers.TypeID AS Type, CustomersFinancialDetails.PaymentTypeID AS class, 
				CustomersFinancialDetails.CreditLimit, CustomersFinancialDetails.CustomerBalance AS bal, 
						  Customers.ChqBalance AS chkbal, Customers.LocationID AS Geo1, Customers.LocationID AS Geo2, Customers.LocationID AS Geo3, Customers.LocationID AS Geo4, 
						  Customers.LocationID AS Geo5, Customers.Barcode, CASE WHEN ISNULL(Customers.Latitude, '0') = '' THEN '0' ELSE ISNULL(Customers.Latitude, '0') END AS Expr1, 
						  CASE WHEN ISNULL(Customers.Longitude, '0') = '' THEN '0' ELSE ISNULL(Customers.Longitude, '0') END AS Expr2, CASE WHEN @ClientActive = 3 then  Customers.Reference2 else 1 end AS PrLevel, 
						  CustomersFinancialDetails.DueDays, CustomersFinancialDetails.ChqsDueDays, CustomersFinancialDetails.TaxInclude, Customers.TelephoneNo, Customers.Email, 
						  Customers.Reference1, Customers.Reference2, IsNull(CustomersFinancialDetails.CreditCash,1), case when @ClientActive = 1 then 1 else CustomersFinancialDetails.AllowChqs end, 
						  0 AS img, Customers.IsSuspended, CustomersFinancialDetails.DiscountPerc, Customers.Address,isnull(CustomersFinancialDetails.MaxInvoiceValue,0),isnull(CustomersFinancialDetails.MaxInvoiceCount,0),isnull([ChqLimit],10000),
						  isnull(CustomersFinancialDetails.Tax_1_Include,0), isnull(CustomersFinancialDetails.Tax_2_Include,0),Customers.Contact,Customers.TaxNumber,
						  IsNull(CustomersFinancialDetails.AllowManualDiscount,0)
FROM            CustomersFinancialDetails INNER JOIN
                         Customers ON CustomersFinancialDetails.CompanyID = Customers.CompanyID AND CustomersFinancialDetails.CustomerID = Customers.ID
WHERE        (CustomersFinancialDetails.CompanyID = @CompNo) AND (CustomersFinancialDetails.RouteID IN
                             (SELECT        RouteID
                                FROM            SalesPersonsAdditionalRoutes
                                WHERE        (CompanyID = @CompNo) AND (PositionID = @PositionsID) AND (WeekNo = @WeekNo) AND (DayNo = @DayOfWeek))) AND 
                         (NOT (CustomersFinancialDetails.CustomerID IN
                             (SELECT        CustomerNo
                                FROM            OSFA_DB.dbo.OT_CustomerMF
                                WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo))))
			  AND (Isnull(CustomersFinancialDetails.RouteID,-1) >= CASE WHEN @OnlyCustomersOnRoutes = 0 THEN -1 ELSE 0 END)

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Insert Additional Routes Customers To OT_CustomerMF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
---------------------------------------------------------------
/*
	DECLARE @cCustomerNo bigint	
	SET @i = 1
	
	DECLARE Customers CURSOR FOR

		SELECT CustomerNo FROM [OSFA_DB].[dbo].[OT_CustomerMF] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)

	OPEN Customers
		FETCH NEXT FROM Customers
		INTO @cCustomerNo
			WHILE @@FETCH_STATUS = 0
			BEGIN
			 
				UPDATE [OSFA_DB].[dbo].[OT_CustomerMF] SET ImageID = @i
				WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (CustomerNo = @cCustomerNo)
			
				SET @i = @i + 1
				
				FETCH NEXT FROM Customers
				INTO @cCustomerNo
			END
	CLOSE Customers
	DEALLOCATE Customers 
	*/
	
 

	if @ClientActive <> 27
	BEGIN
		SET @BeginTime = Convert(varchar(20),GetDate(),108)
		DECLARE @UpdateImageID Table (CustomerNo bigint, ImageID Int, primary key(CustomerNo))
		--;With UpdateImageID  As
		--(
		INSERT INTO @UpdateImageID
		SELECT OSFA_DB.dbo.OT_CustomerMF.CustomerNo,
		ROW_NUMBER() OVER (ORDER BY OSFA_DB.dbo.OT_CustomerMF.CustomerNo DESC) AS ImageID
		FROM OSFA_DB.dbo.OT_CustomerMF
		WHERE  (CompNo = @CompNo) and (SalesmanNo = @SalesmanNo)
		--)
		UPDATE OSFA_DB.dbo.OT_CustomerMF SET ImageID = UpdateImageID.ImageID
		FROM OSFA_DB.dbo.OT_CustomerMF
		INNER JOIN @UpdateImageID AS UpdateImageID ON OSFA_DB.dbo.OT_CustomerMF.CustomerNo = UpdateImageID.CustomerNo
		WHERE  (CompNo = @CompNo) and (SalesmanNo = @SalesmanNo)

		SET @EndTime = Convert(varchar(20),GetDate(),108)
		INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
		VALUES (@CompNo,@SalesmanNo, GETDATE(), 'UpdateImageID In OT_CustomerMF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
	END
	


	--if @ClientActive=30
	--BEGIN
	--	DELETE FROM OSFA_DB.dbo.OT_CustomerMF
	--	WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (IsSuspended = 1)
	--END
---------------------------------------------------------------
/*
SET @BeginTime = Convert(varchar(20),GetDate(),108)

INSERT INTO [OSFA_DB].[dbo].[OT_PriceList]
           ([CompNo]
           ,[SalesmanNo]
           ,[PrNo]
           ,[ItemNo]
           ,[UnitCode]
           ,[SellPrice]
           ,[TaxPerc]
           ,[SellPrice2]
           ,[SellPrice3]
           ,[TaxType]
           ,[DiscountPercent]
           ,UseInReturn
		   ,UseInSales
		   ,Qty
		   ,Tax_1_Type
		   ,Tax_1_Perc
		   ,Tax_2_Type
		   ,Tax_2_Perc)   		   		                
SELECT        PriceLists.CompanyID AS Comp, @SalesmanNo AS SalesM, PriceLists.ID, Items.ItemCode, ItemsUnits.ID AS Expr3, PriceListDetails.Price, CASE WHEN isNULL(items.IsTaxExempt, 0) 
                         = 1 THEN 0 ELSE PriceListDetails.Tax END AS Expr4, ISNULL(PriceListDetails.SellPrice2, 0) AS Expr1, ISNULL(PriceListDetails.SellPrice3, 0) AS Expr2, 
						 case when @ClientActive = 1 THEN 1 ELSE 
						 case when @ClientActive = 30 AND @CompNo <> 3 THEN 1 ELSE PriceListDetails.TaxType END END,
                         PriceListDetails.DiscountPercent, PriceListDetails.UseInReturn, PriceListDetails.UseInSales, ISNULL(PriceListDetails.Qty, 0) AS Qty, IsNull(PriceListDetails.TaxType1,0), IsNull(PriceListDetails.Tax1,0), IsNull(PriceListDetails.TaxType2,0), 
                         IsNUll(PriceListDetails.Tax2,0)
FROM            PriceLists INNER JOIN
                         PriceListDetails ON PriceLists.CompanyID = PriceListDetails.CompanyID AND PriceLists.ID = PriceListDetails.PriceListID INNER JOIN
                         Items ON PriceListDetails.CompanyID = Items.CompanyID AND PriceListDetails.ItemCode = Items.ItemCode INNER JOIN
                         ItemsUnits ON PriceListDetails.CompanyID = ItemsUnits.CompanyID AND PriceListDetails.UnitID = ItemsUnits.ID
WHERE     (PriceLists.ID IN
                          (SELECT     PrNo
                             FROM         OSFA_DB.dbo.OT_CustomerMF
                             WHERE     (CompNo = @CompNo) AND ([SalesmanNo] = @SalesmanNo))) AND (PriceLists.CompanyID = @CompNo)  
		 AND  Items.ItemCode  in (Select ItemNo From OSFA_DB.dbo.OT_ItemsMF Where CompNo = @CompNo AND SalesmanNo = @SalesmanNo)
		 AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, PriceLists.StartDate))<=@SendDate) AND  (DATEADD(DAY, 0, DATEDIFF(DAY, 0, PriceLists.EndDate))>=@SendDate) AND (ISNULL(PriceLists.IsSuspended,0)=0)

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_PriceList [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
*/
---------------------
/*
INSERT INTO [OSFA_DB].[dbo].[OT_PromotionsGroupsCustomersLink]						     
           ([CompNo]
           ,[Prom_GroupID]
           ,[CustomerNo]
           ,[SalesmanNo])
SELECT     CompanyID, CustomersPromotionsGroupsID, CustomerID, @SalesmanNo
FROM         CustomersPromotionsGroupsLink
WHERE     (CompanyID = @CompNo) AND (CustomerID IN
                          (SELECT     CustomerNo
                             FROM         OSFA_DB.dbo.OT_CustomerMF
                             WHERE     (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)))
*/
------------------------
SET @BeginTime = Convert(varchar(20),GetDate(),108)

if @ClientActive = 8  and @CompNo =2 -- Rawabi
BEGIN
	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo
	/*
	IF @SalesmanNo IN (2,3,6,7,10,11,14,15,21,26,27,29,30,31,33,32,34)
	BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,[ForEmp])
	VALUES (@CompNo, @SalesmanNo,3, ' ãÓÊæÏÚ ÇáÈÖÇÆÚ ÇáÌÇåÒå ',' ãÓÊæÏÚ ÇáÈÖÇÆÚ ÇáÌÇåÒå ', 1)
	END

	IF @SalesmanNo IN (10,32,34)
	BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,[ForEmp])
	VALUES (@CompNo, @SalesmanNo,20, ' ãÓÊæÏÚ ÚÕíÑ ÑÇæÈí ',' ãÓÊæÏÚ ÚÕíÑ ÑÇæÈí ', 1)
	END


	IF @SalesmanNo IN (28,31,70,71,72,73,74,75,30)
	BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,[ForEmp])
	VALUES (@CompNo, @SalesmanNo,20, ' ãÓÊæÏÚ ÇáÚÕÇÆÑ ',' ãÓÊæÏÚ ÇáÚÕÇÆÑ ', 1)
	END*/


INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,[ForEmp])
	VALUES (@CompNo, @SalesmanNo,20, ' ãÓÊæÏÚ ÚÕíÑ ÑÇæÈí ',' ãÓÊæÏÚ ÚÕíÑ ÑÇæÈí ', 1)

INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,[ForEmp])
	VALUES (@CompNo, @SalesmanNo,3, ' ãÓÊæÏÚ ÇáÈÖÇÆÚ ÇáÌÇåÒå ',' ãÓÊæÏÚ ÇáÈÖÇÆÚ ÇáÌÇåÒå ', 1)
End
Else
if @ClientActive = 4 -- Zaloum
BEGIN
	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,[ForEmp])
	VALUES (@CompNo, @SalesmanNo,1, 'ãÓÊæÏÚ ÇáÈÓßæÊ ÇáÌÇåÒ','ãÓÊæÏÚ ÇáÈÓßæÊ ÇáÌÇåÒ', 1)

	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,[ForEmp])
	VALUES (@CompNo, @SalesmanNo,4, 'ãÓÊæÏÚ ãæÇÏ ÌÇåÒÉ ÇÛÐíÉ','ãÓÊæÏÚ ãæÇÏ ÌÇåÒÉ ÇÛÐíÉ', 1)
END
if @ClientActive = 55 -- Experts
BEGIN
DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo and @SalesmanNo<>261
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,Reference1
			   ,[ForEmp])
SELECT DISTINCT CompanyID,@SalesmanNo, StoreNo, ArDesc, EngDesc, Reference1, 1 AS Expr1
FROM            ERPStores
WHERE        (CompanyID = @CompNo) and (ERPStores.StoreNo in (select * from [dbo].[Fun_GetTyconzStores](@CompNo , @SalesmanNo)))

END 
 
else if @ClientActive = 145
BEGIN

	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,[ForEmp])

SELECT        CompanyID, @SalesmanNo,StoreNo, ArDesc, ArDesc,1
FROM            ERPStores
where CompanyID=@CompNo
end

ELSE if @ClientActive =20 or @ClientActive=163
BEGIN
	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo 

		INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
				   ([CompNo]
				   ,SalesmanNo
				   ,[StoreNo]
				   ,[ArDesc]
				   ,[EngDesc]
				   ,Reference1
				   ,[ForEmp])
		SELECT DISTINCT ERPStores.CompanyID, @SalesmanNo, ERPStores.StoreNo, ERPStores.ArDesc, ERPStores.EngDesc, ERPStores.Reference1, 1 AS Expr1
		FROM             ERPStores  
		WHERE       (ERPStores.CompanyID = @CompNo)  
	
END

else if @ClientActive = 100   or @ClientActive=134 or @ClientActive=123 or @ClientActive=143
BEGIN

	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,[ForEmp])
	VALUES (@CompNo, @SalesmanNo,1001, 'مستودع الرئيسي','مستودع الرئيسي', 1)


	END

else if @ClientActive = 84 or @ClientActive = 118  or   @ClientActive = 109 or @ClientActive =146 or @ClientActive=137 or @ClientActive=94-- AlNublaa
or @ClientActive=144
BEGIN

	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,[ForEmp])
	VALUES (@CompNo, @SalesmanNo,1, 'Main Store','Main Store', 1)

	END
	else if @ClientActive = 139 
BEGIN

	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,[ForEmp])

SELECT        CompanyID, @SalesmanNo,StoreNo, ArDesc, ArDesc,1
FROM            ERPStores
where CompanyID=@CompNo



	END

ELSE if @ClientActive = 10 -- kasih
BEGIN
	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,[ForEmp])
	VALUES (@CompNo, @SalesmanNo, 301, 'مستودع البضاعة الجاهزة السوق المحلي','مستودع البضاعة الجاهزة السوق المحلي', 1)
	END

Else if  @ClientActive=121
	Begin
		DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo
		INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
				   ([CompNo]
				   ,SalesmanNo
				   ,[StoreNo]
				   ,[ArDesc]
				   ,[EngDesc]
				   ,Reference1
				   ,[ForEmp])
		SELECT DISTINCT ERPStores.CompanyID, SalesPersons.ID, ERPStores.StoreNo, ERPStores.ArDesc, ERPStores.EngDesc, ERPStores.Reference1, 1 AS Expr1
		FROM            SalesPersons INNER JOIN
								 ERPStores ON  SalesPersons.SerialRef  like '%' + ERPStores.Reference2 + '%'   AND SalesPersons.CompanyID = ERPStores.CompanyID
		WHERE        (SalesPersons.ID = @SalesmanNo) AND (ERPStores.CompanyID = @CompNo)

    End
ELSE if @ClientActive = 6 -- ÕáÈÔíÇä
BEGIN
if @SalesmanNo<>281
begin 
DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo and @SalesmanNo<>261
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,Reference1
			   ,[ForEmp])
	VALUES (@CompNo,@SalesmanNo, 1,'MainStore', 'MainStore','1',0)

	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			    ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,Reference1
			   ,[ForEmp])
	VALUES (@CompNo,@SalesmanNo, 3, 'NEAR EXPIRY WAREHOUSE', 'NEAR EXPIRY WAREHOUSE','DAM99', 0)

		INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,Reference1
			   ,[ForEmp])
	VALUES (@CompNo,@SalesmanNo, 2, 'DAMAGED GOODS WAREHOUSE', 'DAMAGED GOODS WAREHOUSE','EXP90', 0)
	end 
END




ELSE IF @ClientActive = 19
BEGIN
	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,[ForEmp])
	select CompNo, @SalesmanNo, StoreNo, StoreName,StoreNameEng,1 
	from DB.dbo.InvStoresMF WHERE CompNo = @CompNo
END
ELSE IF @ClientActive = 17 or @ClientActive = 78 or @ClientActive= 147  --Wadi 
BEGIN
	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,[ForEmp])
Values (@CompNo, @SalesmanNo, 1, 'المستودع الرئيسي','المستودع الرئيسي',1 )

End


ELSE if @ClientActive =117 -- Iraq Sukhtian
BEGIN
	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo 
	IF @CompNo=1
	BEGIN
		INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
				   ([CompNo]
				   ,SalesmanNo
				   ,[StoreNo]
				   ,[ArDesc]
				   ,[EngDesc]
				   ,Reference1
				   ,[ForEmp])
		SELECT DISTINCT ERPStores.CompanyID, SalesPersons.ID, ERPStores.StoreNo, ERPStores.ArDesc, ERPStores.EngDesc, ERPStores.Reference1, 1 AS Expr1
		FROM            SalesPersons INNER JOIN
								 ERPStores ON  SalesPersons.VehicleId  like '%' + ERPStores.Reference2 + '%'   AND SalesPersons.CompanyID = ERPStores.CompanyID
		WHERE        (SalesPersons.ID = @SalesmanNo) AND (ERPStores.CompanyID = @CompNo) and  ERPStores.Reference2 not in ('1','14','19','13')
	END
	ELSE
	BEGIN
	
		INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
				   ([CompNo]
				   ,SalesmanNo
				   ,[StoreNo]
				   ,[ArDesc]
				   ,[EngDesc]
				   ,Reference1
				   ,[ForEmp])
		SELECT DISTINCT ERPStores.CompanyID, StoreNo, ERPStores.StoreNo, ERPStores.ArDesc, ERPStores.EngDesc, ERPStores.Reference1, 1 AS Expr1
		FROM             ERPStores  
		WHERE       (ERPStores.CompanyID = @CompNo)  
	END
END

ELSE if @ClientActive=153 
BEGIN
	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo 

		INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
				   ([CompNo]
				   ,SalesmanNo
				   ,[StoreNo]
				   ,[ArDesc]
				   ,[EngDesc]
				   ,Reference1
				   ,[ForEmp])
		SELECT DISTINCT ERPStores.CompanyID, @SalesmanNo, ERPStores.StoreNo, ERPStores.ArDesc, ERPStores.EngDesc,isnull( ERPStores.Reference2,0), 1 AS Expr1
		FROM             ERPStores  
		WHERE       (ERPStores.CompanyID = @CompNo)  
		 
	
END

ELSE if (@ClientActive =117 and @compno=2) or @ClientActive =131 or @ClientActive =170
begin 
DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo and @SalesmanNo<>261
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,Reference1
			   ,[ForEmp])
	VALUES (@CompNo,@SalesmanNo, 1,'MainStore', 'MainStore','1',0)

	end

ELSE if @ClientActive =74  -- MSG
BEGIN
DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo and @SalesmanNo<>261
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,Reference1
			   ,[ForEmp])
SELECT DISTINCT ERPStores.CompanyID, SalesPersons.ID, ERPStores.StoreNo, ERPStores.ArDesc, ERPStores.EngDesc, ERPStores.Reference1, 1 AS Expr1
FROM            SalesPersons INNER JOIN
                         ERPStores ON  SalesPersons.VehicleId  like '%' + ERPStores.Reference1 + '%'   AND SalesPersons.CompanyID = ERPStores.CompanyID
WHERE        (SalesPersons.ID = @SalesmanNo) AND (ERPStores.CompanyID = @CompNo)

END 

ELSE if    @ClientActive =73  or @ClientActive =133
BEGIN 
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,Reference1
			   ,[ForEmp])
	
		VALUES (@CompNo,@SalesmanNo, 1,'MainStore', 'MainStore','1',0)
		END 

ELSE if @ClientActive =80 -- Hammoudeh
BEGIN
DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo

   INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,Reference1
			   ,[ForEmp])

SELECT     distinct   ERpStores.CompanyID, @SalesmanNo AS Expr1, 0, 0 , 0 ,0, 1
                         
FROM            ERpStores INNER JOIN
                         SalesPersons ON ERpStores.CompanyID = SalesPersons.CompanyID AND  SalesPersons.SerialRef like'%'+ERpStores.Reference1+'%' 
WHERE        (ERpStores.CompanyID = @CompNo) AND (SalesPersons.id= @SalesmanNo)

	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,Reference1
			   ,[ForEmp])

SELECT     distinct   ERpStores.CompanyID, @SalesmanNo AS Expr1, ERPStores.StoreNo, ERpStores.ArDesc , ERpStores.EngDesc ,ERPStores.Reference1, 1
                         
FROM            ERpStores INNER JOIN
                         SalesPersons ON ERpStores.CompanyID = SalesPersons.CompanyID AND  SalesPersons.SerialRef like'%'+ERpStores.Reference1+'%' 
WHERE        (ERpStores.CompanyID = @CompNo) AND (SalesPersons.id= @SalesmanNo)
End
else if @ClientActive = 67 --- Tahoneh
BEGIN
DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo

   INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,Reference1
			   ,[ForEmp])

SELECT     distinct   ERpStores.CompanyID, @SalesmanNo AS Expr1, 0, 0 , 0 ,0, 1
                         
FROM            ERpStores INNER JOIN
                         SalesPersons ON ERpStores.CompanyID = SalesPersons.CompanyID AND  SalesPersons.ForeignName like'%'+ERpStores.Reference1+'%' 
WHERE        (ERpStores.CompanyID = @CompNo) AND (SalesPersons.id= @SalesmanNo)

	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,Reference1
			   ,[ForEmp])

SELECT     distinct   ERpStores.CompanyID, @SalesmanNo AS Expr1, ERPStores.StoreNo, ERpStores.ArDesc , ERpStores.EngDesc ,ERPStores.Reference1, 1
                         
FROM            ERpStores INNER JOIN
                         SalesPersons ON ERpStores.CompanyID = SalesPersons.CompanyID AND SalesPersons.ForeignName like'%'+ERpStores.Reference1+'%' 
WHERE        (ERpStores.CompanyID = @CompNo) AND (SalesPersons.id= @SalesmanNo)
End
ELSE if @ClientActive =111  -- Hayat
BEGIN

	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,[ForEmp])

			   select CompanyID,@SalesmanNo,StoreNo,ArDesc,ArDesc,1 from ERPStores where CompanyID = @CompNo and StoreNo <> 1

 

END 

ELSE if @ClientActive = 27  -- QIMA
BEGIN
	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,Reference1
			   ,[ForEmp])
	SELECT DISTINCT ERPStores.CompanyID, SalesPersons.ID, ERPStores.StoreNo, ERPStores.ArDesc, ERPStores.EngDesc, ERPStores.Reference1, 1 AS Expr1
	FROM            SalesPersons INNER JOIN
							 ERPStores ON SalesPersons.VehicleId LIKE'%'+CAST (ERPStores.StoreNo AS NVARCHAR(max))+'%'
	WHERE        (SalesPersons.ID = @SalesmanNo) AND (ERPStores.CompanyID = @CompNo)
end




ELSE if @ClientActive =30 -- zumot
BEGIN
DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo and @SalesmanNo<>261
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,Reference1
			   ,[ForEmp])
	VALUES (@CompNo,@SalesmanNo, 1,'MainStore', 'MainStore','1',0)

	END
ELSE IF @ClientActive = 22
BEGIN
	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo
	--INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
	--		   ([CompNo]
	--		   ,[StoreNo]
	--		   ,[ArDesc]
	--		   ,[EngDesc]
	--		   ,[ForEmp])
	--select CompNo, StoreNo, StoreName,StoreNameEng,1 
	--from [SERVER\SQL2008].DB.dbo.InvStoresMF WHERE CompNo = @CompNo
END
ELSE IF @ClientActive = 1 -- medica
BEGIN
	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo] = @CompNo
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,[ForEmp])
	SELECT CompNo, @SalesmanNo, StoreNo, StoreName,StoreNameEng,1 
	FROM NewDB.dbo.InvStoresMF 
	WHERE CompNo = @CompNo and StoreNo in(15,16,17,18,91)
END

ELSE IF @ClientActive = 35 -- 'luxury items
BEGIN
	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo] = @CompNo
	

INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			    ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,Reference1
			   ,[ForEmp])
	VALUES (@CompNo, @SalesmanNo, 1, 'luxury items', 'luxury items','1' ,0)

		INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,Reference1
			   ,[ForEmp])
	VALUES (@CompNo, @SalesmanNo, 2, 'Smart Shopping', 'Smart Shopping','2' ,0)

end 

ELSE if @ClientActive in (83,149,160)-- Bladna
BEGIN
DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo 
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,Reference1
			   ,[ForEmp])
	VALUES (@CompNo,@SalesmanNo, 1,'MainStore', 'MainStore','1',0)

	END

ELSE if    @ClientActive =0  
BEGIN 
	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo 

																							   
		INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
				   ([CompNo]
				   ,SalesmanNo
				   ,[StoreNo]
				   ,[ArDesc]
				   ,[EngDesc]
				   ,Reference1
				   ,[ForEmp])
		SELECT DISTINCT ERPStores.CompanyID, @SalesmanNo, ERPStores.StoreNo, ERPStores.ArDesc, ERPStores.EngDesc, ERPStores.Reference1, 1 AS Expr1
									   
																																																	
																																																   
		FROM             ERPStores  
		WHERE       (ERPStores.CompanyID = @CompNo)  
	


--	DELETE FROM [OSFA_DB].[dbo].[OT_Stores] WHERE SalesmanNo = @SalesmanNo and [CompNo]  = @CompNo
--	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
--			   ([CompNo]
--			   ,SalesmanNo
--			   ,[StoreNo]
--			   ,[ArDesc]
--			   ,[EngDesc]
--			   ,Reference1
--			   ,[ForEmp])
--SELECT DISTINCT ERPStores.CompanyID, SalesPersons.ID, ERPStores.StoreNo, ERPStores.ArDesc, ERPStores.EngDesc, ERPStores.Reference1, 0 AS Expr1
--FROM            SalesPersons INNER JOIN
--                         SalesPersonItemsAssignment ON SalesPersons.CompanyID = SalesPersonItemsAssignment.CompanyID AND SalesPersons.PositionID = SalesPersonItemsAssignment.PositionsID INNER JOIN
--                         ERPStoresItemsLink ON SalesPersonItemsAssignment.CompanyID = ERPStoresItemsLink.CompanyID AND SalesPersonItemsAssignment.ItemCode = ERPStoresItemsLink.ItemCode INNER JOIN
--                         ERPStores ON ERPStoresItemsLink.CompanyID = ERPStores.CompanyID AND ERPStoresItemsLink.StoreNo = ERPStores.StoreNo
--WHERE        (SalesPersons.ID = @SalesmanNo) AND (ERPStores.CompanyID = @CompNo)

END 



ELSE
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_Stores]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[StoreNo]
			   ,[ArDesc]
			   ,[EngDesc]
			   ,[ForEmp])
	SELECT     CompanyID, @SalesmanNo, ID, Name AS Ar, Name AS En,1
	FROM         SalesPersons
	WHERE     (ID <> @SalesmanNo) AND (CompanyID = @CompNo)
END

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_Stores [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

-----------------------------
IF @CalcItemBalance = 1
BEGIN

declare @Xtb table(ItemNo nvarchar(100), Qty money)
if @ClientActive= 88  
Begin

	SET @BeginTime = Convert(varchar(20),GetDate(),108)
	if @SalesmanNo not in (10,13,16)
	Begin
	
	insert into @Xtb
	SELECT        TransactionsDetails.ItemCode, SUM(dbo.GetItemOrgUnitQty(@CompNo, TransactionsDetails.ItemCode,
	dbo.GetItemUnitBySerial(@CompNo, TransactionsDetails.ItemCode, 4), (case when TransactionsHeaders.TransactionTypeID in (2,7)
	and (IsNull(TransactionsDetails.ItemStatus,0) in (2,3)) 
	then 0 else
	(TransactionsDetails.Quantity + TransactionsDetails.Bonus) end))) AS Qty
	FROM            TransactionsHeaders INNER JOIN
							 TransactionsDetails ON TransactionsHeaders.CompanyID = TransactionsDetails.CompanyID AND 
							 TransactionsHeaders.TransactionTypeID = TransactionsDetails.TransactionTypeID AND 
							 TransactionsHeaders.TransactionYear = TransactionsDetails.TransactionYear AND 
							 TransactionsHeaders.TransactionNo = TransactionsDetails.TransactionNo
	WHERE        (TransactionsHeaders.CompanyID = @CompNo) AND (TransactionsHeaders.SalesPersonID = @SalesmanNo) 
					AND (ISNULL(TransactionsHeaders.IsVoid,0) <> 1)
					--AND NOT(IsNull(TransactionsDetails.ItemStatus,0) in (2,3))
					AND TransactionsHeaders.TransactionDate > case when @ClientActive = 36 and TransactionsHeaders.CompanyID = 4 then '2017-10-01' 
					else case when  @ClientActive = 73 then   '2021-06-10' else case when @ClientActive = 15 and TransactionsHeaders.CompanyID = 1 then '2022-05-13'  else  '2000-01-01' end end end 
	GROUP BY TransactionsDetails.ItemCode
	
	update SalesPersonItemsBalance
	SET itemQuantity = 0 
	where SalesPersonItemsBalance.SalesPersonID = @SalesmanNo and SalesPersonItemsBalance.CompanyID = @CompNo 

	update SalesPersonItemsBalance
	set itemQuantity = i.Qty
	from @Xtb as i inner join SalesPersonItemsBalance on
				i.ItemNo = SalesPersonItemsBalance.ItemCode 
	where SalesPersonItemsBalance.SalesPersonID = @SalesmanNo and SalesPersonItemsBalance.CompanyID = @CompNo
	
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Calc Items Balances [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
	--select * from @Xtb as i inner join SalesPersonItemsBalance on
	--			i.ItemNo = SalesPersonItemsBalance.ItemCode 
	--where SalesPersonItemsBalance.SalesPersonID = @SalesmanNo and SalesPersonItemsBalance.CompanyID = @CompNo

	End

	End
	else 
	Begin
	SET @BeginTime = Convert(varchar(20),GetDate(),108)
	

	insert into @Xtb
	SELECT        TransactionsDetails.ItemCode,
	case when @ClientActive=155 then Round(SUM(dbo.GetItemOrgUnitQty(@CompNo, TransactionsDetails.ItemCode, dbo.GetItemUnitBySerial(@CompNo, TransactionsDetails.ItemCode, 4),
	(TransactionsDetails.Quantity + TransactionsDetails.Bonus))),3) else
	SUM(dbo.GetItemOrgUnitQty(@CompNo, TransactionsDetails.ItemCode, dbo.GetItemUnitBySerial(@CompNo, TransactionsDetails.ItemCode, 4), TransactionsDetails.Quantity + TransactionsDetails.Bonus)) end AS Qty
	FROM            TransactionsHeaders INNER JOIN
							 TransactionsDetails ON TransactionsHeaders.CompanyID = TransactionsDetails.CompanyID AND 
							 TransactionsHeaders.TransactionTypeID = TransactionsDetails.TransactionTypeID AND 
							 TransactionsHeaders.TransactionYear = TransactionsDetails.TransactionYear AND 
							 TransactionsHeaders.TransactionNo = TransactionsDetails.TransactionNo
	WHERE        (TransactionsHeaders.CompanyID = @CompNo) AND (TransactionsHeaders.SalesPersonID = @SalesmanNo) 
					AND (ISNULL(TransactionsHeaders.IsVoid,0) <> 1)
					AND NOT(IsNull(TransactionsDetails.ItemStatus,0) in (2,3))
					AND TransactionsHeaders.TransactionDate > case when @ClientActive = 36 and TransactionsHeaders.CompanyID = 4 then '2017-10-01' 
					else case when  @ClientActive = 73 then   '2021-06-10' else case when @ClientActive = 15 and TransactionsHeaders.CompanyID = 1 then '2022-05-13'  else  '2000-01-01' end end end 
	GROUP BY TransactionsDetails.ItemCode
	
	update SalesPersonItemsBalance
	SET itemQuantity = 0 
	where SalesPersonItemsBalance.SalesPersonID = @SalesmanNo and SalesPersonItemsBalance.CompanyID = @CompNo 

	update SalesPersonItemsBalance
	set itemQuantity = i.Qty
	from @Xtb as i inner join SalesPersonItemsBalance on
				i.ItemNo = SalesPersonItemsBalance.ItemCode 
	where SalesPersonItemsBalance.SalesPersonID = @SalesmanNo and SalesPersonItemsBalance.CompanyID = @CompNo
	
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Calc Items Balances [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
	--select * from @Xtb as i inner join SalesPersonItemsBalance on
	--			i.ItemNo = SalesPersonItemsBalance.ItemCode 
	--where SalesPersonItemsBalance.SalesPersonID = @SalesmanNo and SalesPersonItemsBalance.CompanyID = @CompNo
	End
END
-----------------------------

SET @BeginTime = Convert(varchar(20),GetDate(),108)

--if @ClientActive = 38
--BEGIN
--	EXEC dbo.Wings_Integ_GetItemBalance @CompNo, @SalesmanNo
--END
if @ClientActive = 137
BEGIN
	EXEC dbo.Wings_Integ_GetItemBalance @CompNo, @SalesmanNo
END

if @ClientActive =148
Begin
Exec [dbo].[Mira_Integ_GetItemBalance_AlRajwa]  @CompNo, @SalesmanNo
End

if @ClientActive = 142
BEGIN
	EXEC dbo.Wings_Integ_GetItemBalance @CompNo, @SalesmanNo
END


if @ClientActive = 117  AND @CompNo=1
BEGIN
	EXEC dbo.Phenix_Sukhtian_Integ_GetItemsBalance @CompNo, @SalesmanNo
END

if @ClientActive = 55
BEGIN
	EXEC dbo.SAP_GetItemBalance @CompNo, @SalesmanNo
END
if @ClientActive = 95
Begin
EXEC dbo.SAP_GetItemBalance_Malak @CompNo ,@SalesmanNo
END
If @ClientActive=74 and @SalesPersonType <> 7 --//MSG
BEGIN

EXEC dbo.X3_Integ_GetItemBalance @CompNo, @SalesmanNo

END

if @ClientActive = 20 and @CompNo=1
begin
Declare @makeInvoice_20 bit =(select MakeSalesInvoice from salespersonsdevicepermissions where CompanyID=@CompNo and PositionsID=@PositionsID) 
if @makeInvoice_20=1
begin
	EXEC [dbo].[PrestoSoft_Integ_GetItemBalance] @CompNo,@SalesmanNo
End
End
else IF @ClientActive = 7 OR (@ClientActive = 24 AND @CompNo = 1) OR (@ClientActive = 42 AND @CompNo = 1 and @SalesmanNo in (133,134,135))
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
	SELECT        CompNo, SalesmanNo, ItemNo, 10000 AS Qty
	FROM            OSFA_DB.dbo.OT_ItemsMF
	WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)  

END
 

ELSE IF @ClientActive = 24 AND @CompNo = 2-- ÑíÊßæ 
BEGIN
	--EXEC [dbo].[SAP_GetItemBalance] @CompNo, @SalesmanNo
	--INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
	--		   ([CompNo]
	--		   ,[StoreNo]
	--		   ,[ItemNo]
	--		   ,[Qty])
	--SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, SalesPersonItemsBalance.ItemCode, 
	--						 SUM([dbo].[GetItemSmallUnitQty] (SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.ItemCode,SalesPersonItemsBalance.UnitCode,SalesPersonItemsBalance.ItemQuantity))
	--FROM            SalesPersonItemsBalance INNER JOIN
	--						 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
	--						 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
	--						 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	--GROUP BY SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, SalesPersonItemsBalance.ItemCode
	--HAVING        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
	
	IF  isnull (@IsMakeOrder,0)=0
	BEGIN
		EXEC [dbo].[SAP_GetItemBalance] @CompNo, @SalesmanNo
		INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
				   ([CompNo]
				   ,[StoreNo]
				   ,[ItemNo]
				   ,[Qty])
		SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, SalesPersonItemsBalance.ItemCode, 
								 SUM([dbo].[GetItemSmallUnitQty] (SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.ItemCode,SalesPersonItemsBalance.UnitCode,SalesPersonItemsBalance.ItemQuantity))
		FROM            SalesPersonItemsBalance INNER JOIN
								 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
								 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
								 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
		GROUP BY SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, SalesPersonItemsBalance.ItemCode
		HAVING        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
	END 
	ELSE 
	BEGIN 


DECLARE @StoreID nvarchar(50)
SELECT @StoreID = Reference2 FROM olives_bo.dbo.SalesPersons WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo)

	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
				   ([CompNo]
				   ,[StoreNo]
				   ,[ItemNo]
				   ,[Qty])
				SELECT DISTINCT @CompNo AS Expr1, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, isnull (SAP_Integration.dbo.ItemBalance.Qty * isnull (Olives_BO.dbo.ItemsUnitsDetails.ConvertRate,1),0) AS Expr2
FROM            OSFA_DB.dbo.OT_ItemsMF INNER JOIN
                         SAP_Integration.dbo.ItemBalance ON OSFA_DB.dbo.OT_ItemsMF.ItemNo COLLATE SQL_Latin1_General_CP1_CI_AS = SAP_Integration.dbo.ItemBalance.ItemNo LEFT OUTER JOIN
                         ItemsUnitsDetails ON OSFA_DB.dbo.OT_ItemsMF.CompNo = ItemsUnitsDetails.CompanyID AND OSFA_DB.dbo.OT_ItemsMF.ItemNo = ItemsUnitsDetails.ItemCode AND 
                         OSFA_DB.dbo.OT_ItemsMF.Unit2 = ItemsUnitsDetails.UnitID
WHERE        (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_ItemsMF.CompNo = @CompNo) AND (SAP_Integration.dbo.ItemBalance.StoreID = @StoreID) 



	UPDATE       OSFA_DB.dbo.OT_ItemsMF
	SET                 QTYOH = SAP_Integration.dbo.ItemBalance.Qty*ConvertRate
	FROM            OSFA_DB.dbo.OT_ItemsMF INNER JOIN
							 SAP_Integration.dbo.ItemBalance ON OSFA_DB.dbo.OT_ItemsMF.ItemNo COLLATE SQL_Latin1_General_CP1_CI_AS = SAP_Integration.dbo.ItemBalance.ItemNo INNER JOIN
							 ItemsUnitsDetails ON OSFA_DB.dbo.OT_ItemsMF.CompNo = ItemsUnitsDetails.CompanyID AND OSFA_DB.dbo.OT_ItemsMF.ItemNo = ItemsUnitsDetails.ItemCode
	WHERE        (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_ItemsMF.CompNo = @compno) AND (SAP_Integration.dbo.ItemBalance.Qty > 0.1) AND 
							 (SAP_Integration.dbo.ItemBalance.StoreID = @StoreID) and 	ItemsUnitsDetails.ConvertRate is not null
	END 
END
ELSE IF @ClientActive = 97 
BEGIN 
	
EXEC [dbo].[SAP_GetItemBalance] @CompNo, @SalesmanNo

delete from [OSFA_DB].[dbo].[OT_StoreItemsQty] where [CompNo]=@CompNo and StoreNo=@SalesmanNo
INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
	
	select distinct CompanyID , SalesPersonID , ItemCode , SUM (Qty) as Qty from (
	SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, SalesPersonItemsBalance.ItemCode, 
							--ROUND ( SUM([dbo].[GetItemSmallUnitQty] (SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.ItemCode,SalesPersonItemsBalance.UnitCode,SalesPersonItemsBalance.ItemQuantity)),1)
						ROUND (sum(SalesPersonItemsBalance.ItemQuantity),1)	as Qty
	FROM            SalesPersonItemsBalance INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
							 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
							 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	GROUP BY SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, SalesPersonItemsBalance.ItemCode
	HAVING        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)


UNION ALL

SELECT     distinct    CompanyID ,   SalesManNo as SalesPersonID , ItemNo  as ItemCode,SUM(SmalLQty) *-1as Qty 
FROM            (SELECT   distinct      1 AS CompanyID, ST_Lamis_CASHVAN.dbo.SalesVoucherItems.VoucherYear, ST_Lamis_CASHVAN.dbo.SalesVoucherItems.VoucherNo, ST_Lamis_CASHVAN.dbo.SalesVoucherItems.ItemNo, dbo.GetItemSmallUnitQty(1, 
                         ST_Lamis_CASHVAN.dbo.SalesVoucherItems.ItemNo, ST_Lamis_CASHVAN.dbo.SalesVoucherItems.ItemNo, ABS(dbo.GetItemOrgUnitQty(1, ST_Lamis_CASHVAN.dbo.SalesVoucherItems.ItemNo, 
                         ST_Lamis_CASHVAN.dbo.SalesVoucherItems.ItemNo, ABS(ST_Lamis_CASHVAN.dbo.SalesVoucherItems.Qty)))) AS SmalLQty, ST_Lamis_CASHVAN.dbo.SalesVoucher.Processed, 
                         ST_Lamis_CASHVAN.dbo.SalesVoucher.SalesManNo
FROM            ST_Lamis_CASHVAN.dbo.SalesVoucherItems INNER JOIN
                         ST_Lamis_CASHVAN.dbo.SalesVoucher ON ST_Lamis_CASHVAN.dbo.SalesVoucherItems.VoucherYear = ST_Lamis_CASHVAN.dbo.SalesVoucher.VoucherYear AND 
                         ST_Lamis_CASHVAN.dbo.SalesVoucherItems.VoucherNo = ST_Lamis_CASHVAN.dbo.SalesVoucher.VoucherNo INNER JOIN
                         ST_Lamis_CASHVAN.dbo.ST_Log ON ST_Lamis_CASHVAN.dbo.SalesVoucherItems.VoucherNo = ST_Lamis_CASHVAN.dbo.ST_Log.VAN_DocNum
WHERE        (ST_Lamis_CASHVAN.dbo.SalesVoucher.Processed IS NULL) AND (ST_Lamis_CASHVAN.dbo.SalesVoucher.SalesManNo = @SalesmanNo) and 
 (ST_Log.DocType = 'I') AND (ST_Log.Status <> N'Success') ) AS XBT
				
GROUP BY CompanyID, ItemNo , SalesManNo  )  as TTT
group by CompanyID , SalesPersonID , ItemCode



/*
	EXEC [dbo].[SAP_GetItemBalance] @CompNo, @SalesmanNo
	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
	SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, SalesPersonItemsBalance.ItemCode, 
							ROUND ( SUM([dbo].[GetItemSmallUnitQty] (SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.ItemCode,SalesPersonItemsBalance.UnitCode,SalesPersonItemsBalance.ItemQuantity)),1)
	FROM            SalesPersonItemsBalance INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
							 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
							 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	GROUP BY SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, SalesPersonItemsBalance.ItemCode
	HAVING        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
	*/


	/*

		select CompanyID , SalesPersonID , ItemCode , SUM (Qty) as Qty from (
	SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, SalesPersonItemsBalance.ItemCode, 
							ROUND ( SUM([dbo].[GetItemSmallUnitQty] (SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.ItemCode,SalesPersonItemsBalance.UnitCode,SalesPersonItemsBalance.ItemQuantity)),1)
							as Qty
	FROM            SalesPersonItemsBalance INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
							 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
							 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	GROUP BY SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, SalesPersonItemsBalance.ItemCode
	HAVING        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
	and ItemCode='FG000130'

UNION ALL

SELECT        CompanyID ,   SalesManNo as SalesPersonID , ItemNo  as ItemCode,SUM(SmalLQty) *-1as Qty 
FROM            (SELECT        1 AS CompanyID, SalesVoucherItems.VoucherYear, SalesVoucherItems.VoucherNo, SalesVoucherItems.ItemNo, Olives_BO.dbo.GetItemSmallUnitQty(1, SalesVoucherItems.ItemNo, SalesVoucherItems.ItemNo, 
                                                    ABS(Olives_BO.dbo.GetItemOrgUnitQty(1, SalesVoucherItems.ItemNo, SalesVoucherItems.ItemNo, ABS(SalesVoucherItems.Qty)))) AS SmalLQty, SalesVoucher.Processed
                          ,SalesManNo
						  FROM            ST_Lamis_CASHVAN..SalesVoucherItems INNER JOIN
                                                    ST_Lamis_CASHVAN..  SalesVoucher ON SalesVoucherItems.VoucherYear = SalesVoucher.VoucherYear AND SalesVoucherItems.VoucherNo = SalesVoucher.VoucherNo
                           WHERE        (SalesVoucher.Processed IS NULL) and SalesManNo=@SalesmanNo ) AS XBT
						   where  ItemNo='FG000130'
GROUP BY CompanyID, ItemNo , SalesManNo  )  as TTT
group by CompanyID , SalesPersonID , ItemCode



	*/
	IF  isnull (@IsMakeOrder,0)=0
	BEGIN
select 0
	END 
	ELSE 
	BEGIN 


--DECLARE @StoreID nvarchar(50)
SELECT @StoreID = Reference2 FROM olives_bo.dbo.SalesPersons WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo)

	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
				   ([CompNo]
				   ,[StoreNo]
				   ,[ItemNo]
				   ,[Qty])
				SELECT DISTINCT @CompNo AS Expr1, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, isnull (SAP_Integration.dbo.ItemBalance.Qty * isnull (Olives_BO.dbo.ItemsUnitsDetails.ConvertRate,1),0) AS Expr2
FROM            OSFA_DB.dbo.OT_ItemsMF INNER JOIN
                         SAP_Integration.dbo.ItemBalance ON OSFA_DB.dbo.OT_ItemsMF.ItemNo COLLATE SQL_Latin1_General_CP1_CI_AS = SAP_Integration.dbo.ItemBalance.ItemNo LEFT OUTER JOIN
                         ItemsUnitsDetails ON OSFA_DB.dbo.OT_ItemsMF.CompNo = ItemsUnitsDetails.CompanyID AND OSFA_DB.dbo.OT_ItemsMF.ItemNo = ItemsUnitsDetails.ItemCode AND 
                         OSFA_DB.dbo.OT_ItemsMF.Unit2 = ItemsUnitsDetails.UnitID
WHERE        (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_ItemsMF.CompNo = @CompNo) AND (SAP_Integration.dbo.ItemBalance.StoreID = @StoreID) 



	UPDATE       OSFA_DB.dbo.OT_ItemsMF
	SET                 QTYOH = SAP_Integration.dbo.ItemBalance.Qty*ConvertRate
	FROM            OSFA_DB.dbo.OT_ItemsMF INNER JOIN
							 SAP_Integration.dbo.ItemBalance ON OSFA_DB.dbo.OT_ItemsMF.ItemNo COLLATE SQL_Latin1_General_CP1_CI_AS = SAP_Integration.dbo.ItemBalance.ItemNo INNER JOIN
							 ItemsUnitsDetails ON OSFA_DB.dbo.OT_ItemsMF.CompNo = ItemsUnitsDetails.CompanyID AND OSFA_DB.dbo.OT_ItemsMF.ItemNo = ItemsUnitsDetails.ItemCode
	WHERE        (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_ItemsMF.CompNo = @compno) AND (SAP_Integration.dbo.ItemBalance.Qty > 0.1) AND 
							 (SAP_Integration.dbo.ItemBalance.StoreID = @StoreID)	
	END 
END
ELSE IF @ClientActive = 55 OR @ClientActive = 61 OR @ClientActive = 82 or @ClientActive=94
BEGIN	
	EXEC [dbo].[SAP_GetItemBalance] @CompNo, @SalesmanNo
	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
	SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, SalesPersonItemsBalance.ItemCode, 
							 SUM([dbo].[GetItemSmallUnitQty] (SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.ItemCode,SalesPersonItemsBalance.UnitCode,SalesPersonItemsBalance.ItemQuantity))
	FROM            SalesPersonItemsBalance INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
							 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
							 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	GROUP BY SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, SalesPersonItemsBalance.ItemCode
	HAVING        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
	
END
ELSE IF @ClientActive = 51 
BEGIN
	EXEC [dbo].[SAP_GetItemBalance] @CompNo, @SalesmanNo
	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
	SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, SalesPersonItemsBalance.ItemCode, 
							 SUM([dbo].[GetItemSmallUnitQty] (SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.ItemCode,SalesPersonItemsBalance.UnitCode,SalesPersonItemsBalance.ItemQuantity))
	FROM            SalesPersonItemsBalance INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
							 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
							 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	GROUP BY SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, SalesPersonItemsBalance.ItemCode
	HAVING        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
	
END

ELSE IF @ClientActive = 35 
BEGIN
IF @IsMakeOrder =1 
begin 
	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
SELECT     CompNo, SalesmanNo, ItemNo, 0 AS Qty
FROM         OSFA_DB.dbo.OT_ItemsMF
WHERE     (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
END 
else 
Begin 
delete   from  [OSFA_DB].[dbo].[OT_StoreItemsQty] WHERE  (CompNo = @CompNo) AND ([StoreNo] = @SalesmanNo)
/*
Remove the comment after update 

INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			  ([CompNo]
			  ,[ItemNo]
			  ,[StoreNo]
			  ,[Qty])


		  SELECT     distinct    Items.CompanyID, Items.ItemCode, SalesPersons.ID, vstock.QTYONHAND
FROM            [LUX].[LUXintegratopn].dbo.vstock  vstock INNER JOIN
                         [LUX].[LUXintegratopn].dbo.vSalesPerson vSalesPerson ON vstock.LOCATION = vSalesPerson.LOCATION INNER JOIN
                         Items ON vstock.Company = Items.Reference2 COLLATE SQL_Latin1_General_CP1_CI_AS AND 
                         vstock.ITEMNO = Items.Reference1 COLLATE Arabic_100_CI_AS_KS INNER JOIN
                         ItemsUnits ON vstock.Company = ItemsUnits.Reference2 COLLATE SQL_Latin1_General_CP1_CI_AS AND 
                         vstock.COSTUNIT = ItemsUnits.Reference1 COLLATE Arabic_100_CI_AS_KS INNER JOIN
                         SalesPersons ON vSalesPerson.CODESLSP = SalesPersons.Reference1 COLLATE Arabic_100_CI_AS_KS AND 
                         vstock.LOCATION = SalesPersons.DeviceID COLLATE Arabic_100_CI_AS_KS
WHERE        (vstock.QTYONHAND > 0) AND (SalesPersons.ID = @SalesmanNo) AND (Items.CompanyID = @CompNo)

*/

delete   from  [OSFA_DB].[dbo].[OT_StoreItemsQty_main] WHERE  (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)


INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty_Main
                         (CompNo, SalesmanNo, StoreNo, ItemNo, Qty)

SELECT        Items.CompanyID, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, 999999 AS MainStore, items.itemcode, Items.QtyInAllStores
FROM            Items INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON Items.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND Items.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
where Items.CompanyID=@CompNo and   OSFA_DB.dbo.OT_ItemsMF.SalesmanNo=@SalesmanNo

		/*	          
SELECT     Items.CompanyID, Items.ItemCode, SalesPersons.ID, cds_integration.dbo.vstock.QTYONHAND
FROM         cds_integration.dbo.vstock INNER JOIN
                      cds_integration.dbo.vSalesPerson ON cds_integration.dbo.vstock.Company = cds_integration.dbo.vSalesPerson.Company AND 
                      cds_integration.dbo.vstock.LOCATION = cds_integration.dbo.vSalesPerson.LOCATION INNER JOIN
                      Items ON cds_integration.dbo.vstock.Company = Items.Reference2 COLLATE SQL_Latin1_General_CP1_CI_AS AND 
                      cds_integration.dbo.vstock.ITEMNO = Items.Reference1 COLLATE Arabic_100_CI_AS_KS INNER JOIN
                      ItemsUnits ON cds_integration.dbo.vstock.Company = ItemsUnits.Reference2 COLLATE SQL_Latin1_General_CP1_CI_AS AND 
                      cds_integration.dbo.vstock.COSTUNIT = ItemsUnits.Reference1 COLLATE Arabic_100_CI_AS_KS INNER JOIN
                      SalesPersons ON cds_integration.dbo.vSalesPerson.Company = SalesPersons.Reference2 COLLATE SQL_Latin1_General_CP1_CI_AS AND 
                      cds_integration.dbo.vSalesPerson.CODESLSP = SalesPersons.Reference1 COLLATE Arabic_100_CI_AS_KS AND 
                      cds_integration.dbo.vstock.LOCATION = SalesPersons.DeviceID COLLATE Arabic_100_CI_AS_KS
WHERE     (cds_integration.dbo.vstock.QTYONHAND > 0) AND (SalesPersons.ID = @SalesmanNo) AND (Items.CompanyID = @CompNo)
*/
/*
delete   from  [OSFA_DB].[dbo].[OT_StoreItemsQty] WHERE  (CompNo = @CompNo) AND ([StoreNo] = @SalesmanNo)
INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			    ,[Qty])
	SELECT        CompNo, SalesmanNo, ItemNo, 10000 AS Qty
	FROM            OSFA_DB.dbo.OT_ItemsMF
	WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
*/
end
                                               
END
/*
ELSE IF @ClientActive = 30
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
	SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, OT_ItemsMF.itemno, 
                       round(  SalesPersonItemsBalance.ItemQuantity,3)
	FROM            SalesPersonItemsBalance INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
							 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
							 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	WHERE        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
	END
	*/
ELSE IF @ClientActive = 30 
Begin
delete   from  [OSFA_DB].[dbo].[OT_StoreItemsQty] WHERE  (CompNo = @CompNo) AND ([StoreNo] = @SalesmanNo)
IF @IsMakeOrder =1 
begin 
	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])

SELECT        OSFA_DB.dbo.OT_ItemsMF.CompNo,  OSFA_DB.dbo.OT_ItemsMF.SalesmanNo ,  OSFA_DB.dbo.OT_ItemsMF.ItemNo, SUM(DB.dbo.InvBatchsMF.QtyOH) as QtyOH 
FROM            DB.dbo.InvBatchsMF INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON DB.dbo.InvBatchsMF.CompNo = OSFA_DB.dbo.OT_ItemsMF.CompNo AND DB.dbo.InvBatchsMF.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo
WHERE        (DB.dbo.InvBatchsMF.CompNo = @CompNo ) AND (DB.dbo.InvBatchsMF.StoreNo = 1) and  (DB.dbo.InvBatchsMF.IsHalt = 0) and 
 OSFA_DB.dbo.OT_ItemsMF.SalesmanNo=@SalesmanNo
GROUP BY OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, DB.dbo.InvBatchsMF.StoreNo


UPDATE       OSFA_DB.dbo.OT_ItemsMF
SET                QtyOH = XBT.QtyOH
FROM            (SELECT        OT_ItemsMF_1.CompNo, OT_ItemsMF_1.SalesmanNo, OT_ItemsMF_1.ItemNo, SUM(DB.dbo.InvBatchsMF.QtyOH) AS QtyOH
                          FROM            DB.dbo.InvBatchsMF INNER JOIN
                                                    OSFA_DB.dbo.OT_ItemsMF AS OT_ItemsMF_1 ON DB.dbo.InvBatchsMF.CompNo = OT_ItemsMF_1.CompNo AND 
                                                    DB.dbo.InvBatchsMF.ItemNo = OT_ItemsMF_1.ItemNo
                          WHERE        (DB.dbo.InvBatchsMF.CompNo = @CompNo) AND (DB.dbo.InvBatchsMF.StoreNo = 1) AND (DB.dbo.InvBatchsMF.IsHalt = 0) AND 
                                                    (OT_ItemsMF_1.SalesmanNo = @SalesmanNo)
                          GROUP BY OT_ItemsMF_1.CompNo, OT_ItemsMF_1.ItemNo, OT_ItemsMF_1.SalesmanNo, DB.dbo.InvBatchsMF.StoreNo) AS XBT INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON XBT.CompNo = OSFA_DB.dbo.OT_ItemsMF.CompNo AND XBT.SalesmanNo = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
                         XBT.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo
       

END 
else 
Begin 
delete   from  [OSFA_DB].[dbo].[OT_StoreItemsQty] WHERE  (CompNo = @CompNo) AND ([StoreNo] = @SalesmanNo)
	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty] 
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])

------------------------------------------------asmar ata
	------SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, OT_ItemsMF.itemno, 
 ------                      round(  SalesPersonItemsBalance.ItemQuantity,3)
	------FROM            SalesPersonItemsBalance INNER JOIN
	------						 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
	------						 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
	------						 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	------WHERE        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo) 


	SELECT        CompNo, SalesManNo, ItemNo,round (QtyOH,3) 
FROM            (SELECT        DB.dbo.InvBatchsMF.CompNo, DB.dbo.InvStoresMF.SalesManNo,DB.dbo.InvBatchsMF.ItemNo, DB.dbo.InvItemsMF.UnitC4, SUM(DB.dbo.InvBatchsMF.QtyOH) AS QtyOH
                          FROM            DB.dbo.InvBatchsMF INNER JOIN
                                                    DB.dbo.InvItemsMF ON DB.dbo.InvBatchsMF.CompNo = DB.dbo.InvItemsMF.CompNo AND DB.dbo.InvBatchsMF.ItemNo = DB.dbo.InvItemsMF.ItemNo INNER JOIN
                                                    DB.dbo.InvStoresMF ON DB.dbo.InvBatchsMF.CompNo = DB.dbo.InvStoresMF.CompNo AND DB.dbo.InvBatchsMF.StoreNo = DB.dbo.InvStoresMF.StoreNo
                          WHERE        (DB.dbo.InvBatchsMF.CompNo = @compno) AND (DB.dbo.InvStoresMF.Employee = 1) AND (NOT (DB.dbo.InvStoresMF.SalesManNo IS NULL)) AND (DB.dbo.InvStoresMF.SalesManNo = @SalesManNo)
                          GROUP BY DB.dbo.InvBatchsMF.CompNo, DB.dbo.InvStoresMF.SalesManNo, DB.dbo.InvBatchsMF.ItemNo, DB.dbo.InvItemsMF.UnitC4) AS XBT
						  where  QtyOH>=0  
	end      
end
ELSE IF @ClientActive = 15 AND @IsMakeOrder = 1
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
	SELECT        CompNo, SalesmanNo, ItemNo, 0 AS Qty
	FROM            OSFA_DB.dbo.OT_ItemsMF
	WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)  
END
ELSE IF @ClientActive = 49 
BEGin
IF @CompNo=1
BEGIN 

delete from   [OSFA_DB].[dbo].[OT_StoreItemsQty] where  [CompNo]=@CompNo and [StoreNo] =@SalesmanNo

						 INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			  ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
SELECT   distinct     OSFA_DB.dbo.OT_ItemsMF.CompNo,@SalesmanNo ,OSFA_DB.dbo.OT_ItemsMF.ItemNo,MicrosoftDynamicsAX12.dbo.RH_CDS_ItemStockBalance.Qty
FROM            MicrosoftDynamicsAX12.dbo.RH_CDS_ItemStockBalance INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON 
                         CompRef+'-'+MicrosoftDynamicsAX12.dbo.RH_CDS_ItemStockBalance.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS = OSFA_DB.dbo.OT_ItemsMF.ItemNo AND 
                         MicrosoftDynamicsAX12.dbo.RH_CDS_ItemStockBalance.CompRef = OSFA_DB.dbo.OT_ItemsMF.Ref5 COLLATE Arabic_CI_AS
WHERE        (OSFA_DB.dbo.OT_ItemsMF.CompNo = @CompNo)  AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
		and 	  Storeid =1001 and Site=100
		and MicrosoftDynamicsAX12.dbo.RH_CDS_ItemStockBalance.Qty >0

End


ELSE 
BEGIN 


delete from   [OSFA_DB].[dbo].[OT_StoreItemsQty] where  [CompNo]=@CompNo and [StoreNo] =@SalesmanNo

						 INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			  ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
SELECT   distinct     OSFA_DB.dbo.OT_ItemsMF.CompNo,@SalesmanNo ,OSFA_DB.dbo.OT_ItemsMF.ItemNo,MicrosoftDynamicsAX12.dbo.RH_CDS_ItemStockBalance.Qty
FROM            MicrosoftDynamicsAX12.dbo.RH_CDS_ItemStockBalance INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON 
                         CompRef+'-'+MicrosoftDynamicsAX12.dbo.RH_CDS_ItemStockBalance.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS = OSFA_DB.dbo.OT_ItemsMF.ItemNo AND 
                         MicrosoftDynamicsAX12.dbo.RH_CDS_ItemStockBalance.CompRef = OSFA_DB.dbo.OT_ItemsMF.Ref5 COLLATE Arabic_CI_AS
WHERE        (OSFA_DB.dbo.OT_ItemsMF.CompNo = @CompNo)  AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
		and 	  Storeid =2001 and Site=200
		and MicrosoftDynamicsAX12.dbo.RH_CDS_ItemStockBalance.Qty >0
END 

END 

else IF @ClientActive = 50 And @CompNo=2 AND @IsMakeOrder = 1 
Begin

print 'aaa'
delete from OSFA_DB.dbo.OT_StoreItemsQty_Main where CompNo=@CompNo and SalesmanNo=@SalesmanNo

INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty_Main
                         (CompNo, SalesmanNo,ItemNo, Qty,StoreNo)
SELECT        OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, SUM(DB.dbo.InvBatchsMF.QtyOH) AS Expr1, 999999 AS QtyOH
FROM            DB.dbo.InvBatchsMF INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON DB.dbo.InvBatchsMF.CompNo = OSFA_DB.dbo.OT_ItemsMF.CompNo AND DB.dbo.InvBatchsMF.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo
WHERE        (DB.dbo.InvBatchsMF.CompNo = @CompNo) AND (DB.dbo.InvBatchsMF.IsHalt = 0) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
and    DB.dbo.InvBatchsMF.StoreNo in (100,101)
GROUP BY OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo

End

 else IF @ClientActive = 50 And @CompNo=1 AND @IsMakeOrder = 1 
Begin

print 'aaa'
delete from OSFA_DB.dbo.OT_StoreItemsQty_Main where CompNo=@CompNo and SalesmanNo=@SalesmanNo

INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty_Main
                         (CompNo, SalesmanNo,ItemNo, Qty,StoreNo)
SELECT        OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, SUM(DB.dbo.InvBatchsMF.QtyOH) AS Expr1, 999999 AS QtyOH
FROM            DB.dbo.InvBatchsMF INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON DB.dbo.InvBatchsMF.CompNo = OSFA_DB.dbo.OT_ItemsMF.CompNo AND DB.dbo.InvBatchsMF.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo
WHERE        (DB.dbo.InvBatchsMF.CompNo = @CompNo) AND (DB.dbo.InvBatchsMF.IsHalt = 0) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
and    DB.dbo.InvBatchsMF.StoreNo in (100)
GROUP BY OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo

End

IF @ClientActive = 117
BEGIN 
print'Sukhtian '

Delete from OSFA_DB.dbo.OT_StoreItemsQty_Main where CompNo=@CompNo and SalesmanNo=@SalesmanNo
INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty_Main
                         (CompNo, SalesmanNo, ItemNo, Qty, StoreNo)
SELECT       distinct  StoresBalances.CompanyID, @SalesmanNo AS Expr1, OSFA_DB.dbo.OT_ItemsMF.ItemNo,   SUM (  StoresBalances.Qty ) AS Expr2, 999999 AS Expr3
FROM            StoresBalances INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON StoresBalances.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo AND 
                         StoresBalances.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
WHERE        (StoresBalances.CompanyID = @CompNo) and StoresBalances.StoreNo in ('WH05',
'WH09',
'WH10',
'WH12')

group by OSFA_DB.dbo.OT_ItemsMF.ItemNo ,StoresBalances.CompanyID
end




-- For Integration Amana Group
ELSE IF @ClientActive = 36 and @CompNo=4
BEGIN
	
	INSERT INTO OSFA_DB.dbo.OT_BatchsInfo (CompNo, SalesmanNo, ItemNo, BatchNo, [ExpireDate], Qty, BatchBarcode)
	SELECT        Companies.ID, @SalesmanNo AS SalesmanNo, SalesIntegration.dbo.ITEMBALANCE.ITEMNO, SalesIntegration.dbo.ITEMBALANCE.INVENTBATCHID, ITEMS_1.EXPDATE, dbo.GetItemSmallUnitQty(@compNo, 
							 SalesIntegration.dbo.ITEMBALANCE.ITEMNO, SalesIntegration.dbo.ITEMBALANCE.UNITID, SalesIntegration.dbo.ITEMBALANCE.QTY) AS Qty, ITEMS_1.BARCODE
	FROM            SalesIntegration.dbo.ITEMBALANCE INNER JOIN
							 Companies ON SalesIntegration.dbo.ITEMBALANCE.COMPANYCODE COLLATE SQL_Latin1_General_CP1256_CI_AS = Companies.Reference1 INNER JOIN
							 SalesPersons ON Companies.ID = SalesPersons.CompanyID AND SalesIntegration.dbo.ITEMBALANCE.STOREID COLLATE SQL_Latin1_General_CP1256_CI_AS = SalesPersons.Reference2 INNER JOIN
							 SalesIntegration.dbo.ITEMS AS ITEMS_1 ON SalesIntegration.dbo.ITEMBALANCE.COMPANYCODE = ITEMS_1.COMPANYCODE AND SalesIntegration.dbo.ITEMBALANCE.ITEMNO = ITEMS_1.ITEMNO AND 
							 SalesIntegration.dbo.ITEMBALANCE.INVENTBATCHID = ITEMS_1.INVENTBATCHID
	WHERE        (Companies.ID = @compNo) AND (SalesIntegration.dbo.ITEMBALANCE.QTY >= 0) AND (SalesPersons.id=@SalesmanNo)
		
	INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty (CompNo, StoreNo, ItemNo, Qty)
	SELECT        Companies.ID, @SalesmanNo AS SalesmanNo, SalesIntegration.dbo.ITEMBALANCE.ITEMNO, SUM(dbo.GetItemSmallUnitQty(@compNo, SalesIntegration.dbo.ITEMBALANCE.ITEMNO, 
							 SalesIntegration.dbo.ITEMBALANCE.UNITID, SalesIntegration.dbo.ITEMBALANCE.QTY)) AS Qty
	FROM            SalesIntegration.dbo.ITEMBALANCE INNER JOIN
							 Companies ON SalesIntegration.dbo.ITEMBALANCE.COMPANYCODE COLLATE SQL_Latin1_General_CP1256_CI_AS = Companies.Reference1 INNER JOIN
							 SalesPersons ON Companies.ID = SalesPersons.CompanyID AND SalesIntegration.dbo.ITEMBALANCE.STOREID COLLATE SQL_Latin1_General_CP1256_CI_AS = SalesPersons.Reference2 INNER JOIN
							 SalesIntegration.dbo.ITEMS AS ITEMS_1 ON SalesIntegration.dbo.ITEMBALANCE.COMPANYCODE = ITEMS_1.COMPANYCODE AND SalesIntegration.dbo.ITEMBALANCE.ITEMNO = ITEMS_1.ITEMNO AND 
							 SalesIntegration.dbo.ITEMBALANCE.INVENTBATCHID = ITEMS_1.INVENTBATCHID
	WHERE        (Companies.ID = @compNo) AND (SalesIntegration.dbo.ITEMBALANCE.QTY >= 0) AND (SalesPersons.id=@SalesmanNo)
	GROUP BY Companies.ID, SalesIntegration.dbo.ITEMBALANCE.ITEMNO
END

Else if  @ClientActive = 13 
BEGIN 


if @IsMakeOrder =1 
Begin
select '13a AbuOdehinsertQtysQuerry'
delete from OSFA_DB.dbo.OT_StoreItemsQty_Main where CompNo=@CompNo and SalesmanNo=@SalesmanNo
INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty_Main
                         (CompNo, SalesmanNo,ItemNo, Qty,StoreNo)

SELECT        OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, SUM(xxx.Qty) ,999999
                         AS QtyOH
FROM            StoresBalances as xxx INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON xxx.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
                         xxx.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo INNER JOIN
                         SalesPersons ON xxx.companyID = SalesPersons.CompanyID AND xxx.StoreNo = SalesPersons.reference2 AND 
                         OSFA_DB.dbo.OT_ItemsMF.CompNo = SalesPersons.CompanyID AND OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = SalesPersons.ID
WHERE        (xxx.CompanyID = @CompNo)  
AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
GROUP BY OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, xxx.StoreNo
END
else
Begin
EXEC    [dbo].[ABS_Integ_GetItemBalance_AbuOdeh] @CompNo, @SalesmanNo
END
END



ELSE IF @ClientActive=60
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
SELECT        OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, ISNULL (Round(SalesPersonItemsBalance.ItemQuantity,2),0)
FROM            SalesPersonItemsBalance RIGHT OUTER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
                         SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
WHERE        (OSFA_DB.dbo.OT_ItemsMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)

END
ELSE IF @ClientActive = 38 or @ClientActive = 66 Or @ClientActive=50
 BEGIN
 delete   from  [OSFA_DB].[dbo].[OT_StoreItemsQty] WHERE  (CompNo = @CompNo) AND ([StoreNo] = @SalesmanNo)
INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
           ([CompNo]
           ,[StoreNo]
           ,[ItemNo]
           ,[Qty])
   SELECT        OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo,ROUND (ISNULL  (SalesPersonItemsBalance.ItemQuantity,0),3)
FROM            OSFA_DB.dbo.OT_ItemsMF LEFT OUTER JOIN
                         SalesPersonItemsBalance ON OSFA_DB.dbo.OT_ItemsMF.ItemNo = SalesPersonItemsBalance.ItemCode AND OSFA_DB.dbo.OT_ItemsMF.CompNo = SalesPersonItemsBalance.CompanyID AND 
                         OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = SalesPersonItemsBalance.SalesPersonID
WHERE        (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_ItemsMF.CompNo = @CompNo) 
 END





 ELSE if @ClientActive = 117
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
	SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, OT_ItemsMF.itemno, 
                        [dbo].[GetItemSmallUnitQty] (SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.ItemCode,SalesPersonItemsBalance.UnitCode,SalesPersonItemsBalance.ItemQuantity)
	FROM            SalesPersonItemsBalance INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
							 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
							 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	WHERE        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
	end
	else if @ClientActive=118
BEGIN
delete from [OSFA_DB].[dbo].[OT_StoreItemsQty] where CompNo=@CompNo and StoreNo=@SalesmanNo
			  
	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])

			SELECT CompanyID, SalesPersonID, aa.ItemNo, Sum(ItemQuantity) as ItemQuantity
FROM     (SELECT SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, OSFA_DB.dbo.OT_ItemsMF.ItemNo, SalesPersonItemsBalance.ItemQuantity
                  FROM      SalesPersonItemsBalance INNER JOIN
                                    OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
                                    SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
                 WHERE   (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
                  UNION ALL
                  SELECT xbt.CompanyID, xbt.ID, xbt.ItemCode, 0 AS QTY
                  FROM     (SELECT SalesPersons.CompanyID, SalesPersons.ID, SalesPersonItemsAssignment.ItemCode
                                    FROM      SalesPersons INNER JOIN
                                                      SalesPersonItemsAssignment ON SalesPersons.CompanyID = SalesPersonItemsAssignment.CompanyID AND SalesPersons.PositionID = SalesPersonItemsAssignment.PositionsID
                                        WHERE   (SalesPersons.ID = @SalesmanNo) AND (SalesPersons.CompanyID = @CompNo)) AS xbt) AS aa
									inner join    OSFA_DB.dbo.OT_ItemsMF OT_ItemsMF on aa.CompanyID=OT_ItemsMF.CompNo and OT_ItemsMF.ItemNo=aa.ItemNo
									 and aa.SalesPersonID=OT_ItemsMF.SalesmanNo
group by CompanyID, SalesPersonID, aa.ItemNo

	/*SELECT     CompanyID, SalesPersonID, ItemCode, ItemQuantity
	FROM         SalesPersonItemsBalance
	WHERE     (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo)   */
END


ELSE if @ClientActive=122
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])

			   SELECT        OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, ISNULL(SalesPersonItemsBalance.ItemQuantity,0)
FROM            SalesPersonItemsBalance RIGHT OUTER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
                         SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	WHERE        (OSFA_DB.dbo.OT_ItemsMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
	



	/*SELECT     CompanyID, SalesPersonID, ItemCode, ItemQuantity
	FROM         SalesPersonItemsBalance
	WHERE     (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo)   */
END

 ELSE if @ClientActive=80
BEGIN

	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])

  
SELECT        CompanyID, SalesPersonID, ItemNo, Qty
FROM            (SELECT        dd.CompanyID, dd.SalesPersonID, dd.ItemNo, dd.qty - ISNULL(derivedtbl_2.Qty, 0) AS Qty
                           FROM            (SELECT        aa.CompanyID, aa.SalesPersonID, aa.ItemNo, aa.ItemQuantity - ISNULL(derivedtbl_1.qty, 0) AS qty
                                                      FROM            (SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, OSFA_DB.dbo.OT_ItemsMF.ItemNo, SalesPersonItemsBalance.ItemQuantity
                                                                                 FROM            SalesPersonItemsBalance INNER JOIN
                                                                                                          OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
                                                                                                          SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
                                                                                 WHERE        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)) AS aa LEFT OUTER JOIN
                                                                                   (SELECT        CompanyID, SalesPersonID, ItemCode, qty
                                                                                      FROM            (SELECT        TransactionsHeaders.CompanyID, TransactionsHeaders.SalesPersonID, TransactionsDetails.ItemCode, SUM(ABS(TransactionsDetails.Quantity)) AS qty
                                                                                                                 FROM            TransactionsHeaders INNER JOIN
                                                                                                                                          TransactionsDetails ON TransactionsHeaders.CompanyID = TransactionsDetails.CompanyID AND 
                                                                                                                                          TransactionsHeaders.TransactionTypeID = TransactionsDetails.TransactionTypeID AND 
                                                                                                                                          TransactionsHeaders.TransactionYear = TransactionsDetails.TransactionYear AND 
                                                                                                                                          TransactionsHeaders.TransactionNo = TransactionsDetails.TransactionNo
                                                                                                                 WHERE        (TransactionsHeaders.CompanyID = @CompNo) AND (TransactionsHeaders.SalesPersonID = @SalesmanNo) AND 
                                                                                                                                          (TransactionsHeaders.PostedToERP IS NULL) AND (TransactionsHeaders.IsVoid = 0) AND (TransactionsHeaders.Approve IS NULL) AND 
                                                                                                                                        --  (TransactionsHeaders.TransactionDate = CAST(GETDATE() AS date)) AND
																																		   (TransactionsHeaders.TransactionTypeID = 1)
                                                                                                                 GROUP BY TransactionsHeaders.CompanyID, TransactionsDetails.ItemCode, TransactionsHeaders.SalesPersonID) AS xbt) AS derivedtbl_1 ON 
                                                                               aa.CompanyID = derivedtbl_1.CompanyID AND aa.SalesPersonID = derivedtbl_1.SalesPersonID AND aa.ItemNo = derivedtbl_1.ItemCode) AS dd LEFT OUTER JOIN
                                                        (SELECT        @CompNo AS CompanyID, SalesPersons.ID AS SalesManNo, ST_JPPMC_CASH_VAN1.dbo.SalesVoucherItems.ItemNo, SUM(ST_JPPMC_CASH_VAN1.dbo.SalesVoucherItems.Qty) 
                                                                                    AS Qty
                                                           FROM            ST_JPPMC_CASH_VAN1.dbo.SalesVoucher INNER JOIN
                                                                                    ST_JPPMC_CASH_VAN1.dbo.SalesVoucherItems ON ST_JPPMC_CASH_VAN1.dbo.SalesVoucher.VoucherYear = ST_JPPMC_CASH_VAN1.dbo.SalesVoucherItems.VoucherYear AND 
                                                                                    ST_JPPMC_CASH_VAN1.dbo.SalesVoucher.VoucherNo = ST_JPPMC_CASH_VAN1.dbo.SalesVoucherItems.VoucherNo INNER JOIN
                                                                                    SalesPersons ON ST_JPPMC_CASH_VAN1.dbo.SalesVoucher.SalesManNo = SalesPersons.Reference1
                                                           WHERE        (SalesPersons.ID = @SalesmanNo) AND (ST_JPPMC_CASH_VAN1.dbo.SalesVoucher.Processed IS NULL)
                                                           GROUP BY ST_JPPMC_CASH_VAN1.dbo.SalesVoucherItems.Unit, ST_JPPMC_CASH_VAN1.dbo.SalesVoucherItems.ItemNo, ST_JPPMC_CASH_VAN1.dbo.SalesVoucher.SalesManNo, 
                                                                                    SalesPersons.ID) AS derivedtbl_2 ON dd.CompanyID = derivedtbl_2.CompanyID AND dd.SalesPersonID = derivedtbl_2.SalesManNo AND dd.ItemNo = derivedtbl_2.ItemNo) 
                         AS aa
WHERE        (Qty > 0)

--SELECT        aa.CompanyID, aa.SalesPersonID, aa.ItemNo, aa.ItemQuantity-ISNULL(derivedtbl_1.qty,0) as qty
--FROM            (SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, OSFA_DB.dbo.OT_ItemsMF.ItemNo, SalesPersonItemsBalance.ItemQuantity
--                           FROM            SalesPersonItemsBalance INNER JOIN
--                                                    OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
--                                                    SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
--                           WHERE        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)) AS aa LEFT OUTER JOIN
--                             (SELECT        CompanyID, SalesPersonID, ItemCode, qty
--                                FROM            (SELECT        TransactionsHeaders.CompanyID, TransactionsHeaders.SalesPersonID, TransactionsDetails.ItemCode, SUM(ABS(TransactionsDetails.Quantity)) AS qty
--                                                           FROM            TransactionsHeaders INNER JOIN
--                                                                                    TransactionsDetails ON TransactionsHeaders.CompanyID = TransactionsDetails.CompanyID AND 
--                                                                                    TransactionsHeaders.TransactionTypeID = TransactionsDetails.TransactionTypeID AND TransactionsHeaders.TransactionYear = TransactionsDetails.TransactionYear AND 
--                                                                                    TransactionsHeaders.TransactionNo = TransactionsDetails.TransactionNo
--                                                           WHERE        (TransactionsHeaders.CompanyID = @CompNo) AND (TransactionsHeaders.SalesPersonID = @SalesmanNo) AND (TransactionsHeaders.PostedToERP IS NULL) AND 
--                                                                       TransactionsHeaders.IsVoid=0            and (TransactionsHeaders.Approve IS NULL) AND (TransactionsHeaders.TransactionDate = CAST(GETDATE() AS date)) AND (TransactionsHeaders.TransactionTypeID = 1)
--                                                           GROUP BY TransactionsHeaders.CompanyID, TransactionsDetails.ItemCode, TransactionsHeaders.SalesPersonID) AS xbt) AS derivedtbl_1 ON aa.CompanyID = derivedtbl_1.CompanyID AND 
--                         aa.SalesPersonID = derivedtbl_1.SalesPersonID AND aa.ItemNo = derivedtbl_1.ItemCode

END


else if @ClientActive=107 
Begin

if @IsMakeOrder=1 
Begin

declare @StoreSalesman  nvarchar(50)
select @StoreSalesman=Reference2 from Olives_BO..SalesPersons where CompanyID=@CompNo and id=@SalesmanNo and Reference2<>''
delete from [OSFA_DB].[dbo].[OT_StoreItemsQty] where CompNo=@CompNo and StoreNo=@SalesmanNo
INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
				   ([CompNo]
				   ,[StoreNo]
				   ,[ItemNo]
				   ,[Qty])

SELECT        @CompNo, @SalesmanNo, ItemCode, Qty
FROM            StoresBalances
where CompanyID=@CompNo  and StoreNo=cast (@StoreSalesman as nvarchar(50))
End

else 
Begin

	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
	SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, OT_ItemsMF.itemno, 
                         SalesPersonItemsBalance.ItemQuantity
	FROM            SalesPersonItemsBalance INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
							 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
							 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	WHERE        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)

	delete from  OSFA_DB.[dbo].[OT_StoreItemsQty_Main] where [CompNo]=@CompNo and [SalesmanNo]=@SalesmanNo
	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty_Main]
				   ([CompNo]
				   ,[StoreNo]
				   ,[SalesmanNo]
				   ,[ItemNo]
				   ,[Qty])
		
		SELECT        @CompNo, 999999,@SalesmanNo, ItemCode, Qty
FROM            StoresBalances
where CompanyID=@CompNo  and StoreNo='01'
End

END


ELSE if @ClientActive=95
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
	SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, OT_ItemsMF.itemno, 
                         [dbo].[GetItemSmallUnitQty] ( SalesPersonItemsBalance.CompanyID , OT_ItemsMF.itemno,SalesPersonItemsBalance.UnitCode , SalesPersonItemsBalance.ItemQuantity  )   as ItemQuantity
	FROM            SalesPersonItemsBalance INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
							 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
							 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	WHERE        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
	
END




 Else if @ClientActive=52
 Begin

Declare @makeInvoice bit =(select MakeSalesInvoice  from SalesPersonsDevicePermissions where PositionsID=@PositionsID and CompanyID=@CompNo) 
if @CompNo=2
 Begin
if @makeInvoice=1
Begin
INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])

SELECT     Distinct   SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, OSFA_DB.dbo.OT_ItemsMF.ItemNo, SalesPersonItemsBalance.ItemQuantity
FROM            SalesPersonItemsBalance INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
                         SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo INNER JOIN
                         Items ON SalesPersonItemsBalance.CompanyID = Items.CompanyID AND SalesPersonItemsBalance.ItemCode = Items.ItemCode
WHERE        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
and CategCode <>112
	             
	
				 Union all
				 --select * from ItemsCategories where CompanyID=2
select Distinct D.companyid companyid,SS.ID SalesPersonID,D.ItemCode itemno,100000 itemquantity
from OSFA_DB.dbo.OT_ItemsMF as S inner join items as D on S.CompNo=D.CompanyID and S.itemno=D.ItemCode
inner join salespersons as SS on S.compno=SS.CompanyID 
where CategCode=112 and D.CompanyID=@CompNo and SS.id=@SalesmanNo and @makeInvoice=1
END 
Else 
Begin
INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])

SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, OT_ItemsMF.itemno, 
                         SalesPersonItemsBalance.ItemQuantity
	FROM            SalesPersonItemsBalance INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
							 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
							 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	WHERE        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
	             and itemcode not in ('01-10040')
				
				 Union all

select Distinct D.companyid companyid,SS.ID SalesPersonID,D.ItemCode itemno,100000 itemquantity
from OSFA_DB.dbo.OT_ItemsMF as S inner join items as D on S.CompNo=D.CompanyID and S.itemno=D.ItemCode
inner join salespersons as SS on S.compno=SS.CompanyID 
where itemcode in('01-10040') and D.CompanyID=@CompNo and SS.id=@SalesmanNo and @makeInvoice=1
END



 END

 else 
 begin

 INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])

 select Distinct D.companyid companyid,SS.ID SalesPersonID,D.ItemCode itemno,100000 itemquantity
from OSFA_DB.dbo.OT_ItemsMF as S inner join items as D on S.CompNo=D.CompanyID and S.itemno=D.ItemCode
inner join salespersons as SS on S.compno=SS.CompanyID 
where D.CompanyID=@CompNo and SS.id=@SalesmanNo and @makeInvoice=1

 /*

INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])

SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, OT_ItemsMF.itemno, 
                         SalesPersonItemsBalance.ItemQuantity
	FROM            SalesPersonItemsBalance INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
							 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
							 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	WHERE        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
	            -- and Categ<>104

				-- Union all

--select Distinct D.companyid companyid,SS.ID SalesPersonID,D.ItemCode itemno,100000 itemquantity
--from OSFA_DB.dbo.OT_ItemsMF as S inner join items as D on S.CompNo=D.CompanyID and S.itemno=D.ItemCode
--inner join salespersons as SS on S.compno=SS.CompanyID 
--where D.CategCode=104 and D.CompanyID=@CompNo and SS.id=@SalesmanNo and @makeInvoice=1
*/
 end

 END


 ELSE if  @ClientActive=142
begin
	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
	SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, OT_ItemsMF.itemno, 
                         SalesPersonItemsBalance.ItemQuantity
	FROM            SalesPersonItemsBalance INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
							 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
							 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	WHERE        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
	and SalesPersonItemsBalance.ItemQuantity>0

END
ELSE if @ClientActive=85 and @CompNo=1 and @SalesmanGroupID=4
begin

	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
	SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, OT_ItemsMF.itemno, 
                         SalesPersonItemsBalance.ItemQuantity
	FROM            SalesPersonItemsBalance INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
							 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
							 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	WHERE        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
	Union All
	select @CompNo,@SalesmanNo,'Card',5

END


--/////////////////////////////////////// GCI ////////////////////////////
Else if @ClientActive =165
Begin

Select @StoreNo = ForeignName from SalesPersons where CompanyID=@CompNo and ID = @SalesmanNo

	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])

select distinct  CompanyID,@SalesmanNo,ItemCode,0 as [Qty] from SalesPersonItemsAssignment 
where CompanyID=@CompNo and PositionsID=@PositionsID

--Exec OT_SendSalesmanData 2,10 --gci
Delete from osfa_DB..OT_StoreItemsQty_Main where SalesmanNo=@SalesmanNo and compno=@CompNo

insert into  osfa_DB..OT_StoreItemsQty_Main
				([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])

select Distinct S.CompNo,@SalesmanNo ,S.StoreNo,S.ItemNo,S.Qty
from osfa_DB..OT_StoreItemsQty_Main_ERP as S
inner join Customers as C on S.CompNo=C.CompanyID and S.StoreNo=C.Erp_Reference
inner join CustomersFinancialDetails as F on C.CompanyID=F.CompanyID and C.id=F.CustomerID and PositionsID=@PositionsID
left outer join osfa_DB..OT_StoreItemsQty_Main as D on S.CompNo=D.compno and S.StoreNo=D.StoreNo and S.itemno=D.itemno   
where S.CompNo=@CompNo and salesmanno is null

Select * from osfa_DB..OT_StoreItemsQty_Main where salesmanno=@SalesmanNo

INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty_Main]
			   ([CompNo]
			   ,SalesmanNo
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
SELECT     distinct   SalesPersonItemsAssignment.CompanyID, @SalesmanNo AS Expr1,ERPStores.StoreNo, SalesPersonItemsAssignment.ItemCode, 0 AS Qty
FROM            SalesPersonItemsAssignment INNER JOIN
                         ERPStores ON SalesPersonItemsAssignment.CompanyID = ERPStores.CompanyID
WHERE        (SalesPersonItemsAssignment.CompanyID = @CompNo) AND (SalesPersonItemsAssignment.PositionsID = @PositionsID) and ItemCode not in
(select itemcode from [OSFA_DB].[dbo].[OT_StoreItemsQty_Main] where
CompNo=@CompNo and SalesmanNo=@SalesmanNo) 

end

Else if @ClientActive=15
begin
select 'DefafStores'
    Delete from osfa_db..OT_StoreItemsQty WHERE  (CompNo = @CompNo) AND ([StoreNo] = @SalesmanNo)
	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
	SELECT         SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, OT_ItemsMF.itemno, 
                         round(SalesPersonItemsBalance.ItemQuantity,1)
	FROM            SalesPersonItemsBalance INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
							 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
							 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	WHERE        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
	/*SELECT     CompanyID, SalesPersonID, ItemCode, ItemQuantity
	FROM         SalesPersonItemsBalance
	WHERE     (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo)   */


end
ELSE iF @ClientActive=176
BEGIN 


Delete from OSFA_DB.dbo.OT_StoreItemsQty where CompNo=@CompNo and StoreNo=@SalesmanNo
  
select  @Ref2 = isnull (SalesPersons.Reference2,'0') from SalesPersons where ID =@SalesmanNo and CompanyID=@CompNo

INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty
                         (CompNo, StoreNo, ItemNo, Qty)

SELECT        @CompNo AS Expr1, @SalesmanNo AS Expr2, SalesPersonItemsAssignment.ItemCode, ISNULL(CitMultiStore.dbo.WHStock_V.Quantity, 0) AS Expr3
FROM            SalesPersons INNER JOIN
                         SalesPersonItemsAssignment ON SalesPersons.PositionID = SalesPersonItemsAssignment.PositionsID AND SalesPersons.CompanyID = SalesPersonItemsAssignment.CompanyID INNER JOIN
                         CitMultiStore.dbo.WHStock_V ON SalesPersons.Reference2 = CitMultiStore.dbo.WHStock_V.StoreNo AND 
                         SalesPersonItemsAssignment.ItemCode = CitMultiStore.dbo.WHStock_V.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS
WHERE        (SalesPersonItemsAssignment.CompanyID = @CompNo) AND (CitMultiStore.dbo.WHStock_V.StoreNo = @Ref2) AND (SalesPersonItemsAssignment.PositionsID = @SalesmanNo)
END 



Else if @ClientActive=15 and @CompNo=3 and @IsMakeOrder=0
begin
INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
	SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, OT_ItemsMF.itemno, 
                         SalesPersonItemsBalance.ItemQuantity
	FROM            SalesPersonItemsBalance INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
							 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
							 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	WHERE        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
END

ELSE
begin

Select 'Default ot_storeitemqty'

	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
			   ([CompNo]
			   ,[StoreNo]
			   ,[ItemNo]
			   ,[Qty])
	SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, OT_ItemsMF.itemno, 
                         SalesPersonItemsBalance.ItemQuantity
	FROM            SalesPersonItemsBalance INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
							 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
							 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	WHERE        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
	/*SELECT     CompanyID, SalesPersonID, ItemCode, ItemQuantity
	FROM         SalesPersonItemsBalance
	WHERE     (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo)   */
END




 

 IF @ClientActive = 50 And @CompNo=1 AND @IsMakeInvoice = 1
Begin

print 'aaa'
delete from OSFA_DB.dbo.OT_StoreItemsQty_Main where CompNo=@CompNo and SalesmanNo=@SalesmanNo

INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty_Main
                         (CompNo, SalesmanNo,ItemNo, Qty,StoreNo)
SELECT        OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, SUM(DB.dbo.InvBatchsMF.QtyOH) AS Expr1, 999999 AS QtyOH
FROM            DB.dbo.InvBatchsMF INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON DB.dbo.InvBatchsMF.CompNo = OSFA_DB.dbo.OT_ItemsMF.CompNo AND DB.dbo.InvBatchsMF.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo
WHERE        (DB.dbo.InvBatchsMF.CompNo = @CompNo) AND (DB.dbo.InvBatchsMF.IsHalt = 0) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
and    DB.dbo.InvBatchsMF.StoreNo in (100)
GROUP BY OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo

End

iF @ClientActive=176
BEGIN 


Delete from OSFA_DB.dbo.OT_StoreItemsQty where CompNo=@CompNo and StoreNo=@SalesmanNo
  
--select  @Ref2 = isnull (SalesPersons.Reference2,'0') from SalesPersons where ID =@SalesmanNo and CompanyID=@CompNo

--INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty
--                         (CompNo, StoreNo, ItemNo, Qty)

--SELECT        @CompNo AS Expr1, @SalesmanNo AS Expr2, SalesPersonItemsAssignment.ItemCode, ISNULL(CitMultiStore.dbo.WHStock_V.Quantity, 0) AS Expr3
--FROM            SalesPersons INNER JOIN
--                         SalesPersonItemsAssignment ON SalesPersons.PositionID = SalesPersonItemsAssignment.PositionsID AND SalesPersons.CompanyID = SalesPersonItemsAssignment.CompanyID INNER JOIN
--                         CitMultiStore.dbo.WHStock_V ON SalesPersons.Reference2 = CitMultiStore.dbo.WHStock_V.StoreNo AND 
--                         SalesPersonItemsAssignment.ItemCode = CitMultiStore.dbo.WHStock_V.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS
--WHERE        (SalesPersonItemsAssignment.CompanyID = @CompNo) AND (CitMultiStore.dbo.WHStock_V.StoreNo = @Ref2) AND (SalesPersonItemsAssignment.PositionsID = @SalesmanNo)
--END 

INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty_Main
                         (CompNo, SalesmanNo,ItemNo, Qty,StoreNo)

SELECT distinct @CompNo,@SalesmanNo,CitMultiStore.dbo.InvStoreItem.ItemNo, CitMultiStore.dbo.InvStoreItem.OnlineQty AS Quantity,'999999' 
FROM            CitMultiStore.[dbo].InvStoreItem  LEFT OUTER JOIN
                          CitMultiStore.[dbo].InvGenericItem ON CitMultiStore.[dbo].InvStoreItem.ItemNo = CitMultiStore.[dbo].InvGenericItem.ItemNo
WHERE        (CitMultiStore.[dbo].InvStoreItem.OnlineQty > 0) and StoreNo=1
END

    
--UPDATE    OSFA_DB.dbo.OT_StoreItemsQty
--SET              Qty = OSFA_DB.dbo.OT_StoreItemsQty.Qty * (OSFA_DB.dbo.OT_ItemsMF.Conv1 * OSFA_DB.dbo.OT_ItemsMF.Conv2 * OSFA_DB.dbo.OT_ItemsMF.Conv3)
--FROM         OSFA_DB.dbo.OT_StoreItemsQty INNER JOIN
--                      OSFA_DB.dbo.OT_ItemsMF ON OSFA_DB.dbo.OT_StoreItemsQty.CompNo = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
--                      OSFA_DB.dbo.OT_StoreItemsQty.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo
--WHERE     (OSFA_DB.dbo.OT_StoreItemsQty.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo) AND 
--                      (OSFA_DB.dbo.OT_StoreItemsQty.StoreNo = @SalesmanNo)

IF @ClientActive = 86
BEGIN 

delete from OSFA_DB.dbo.OT_StoreItemsQty_Main where CompNo=@CompNo and SalesmanNo=@SalesmanNo
INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty_Main
                         (CompNo, SalesmanNo,ItemNo, Qty,StoreNo)

						 
						 SELECT        @CompNo,@SalesmanNo, ItemNo, sum (Quantity) , 999999
FROM            CitMultiStore.dbo.WHStock_V
WHERE StoreNo =1
GROUP BY ITEMNO,STORENO 
END

declare @IsMakeTransfear bit 
SELECT        @IsMakeTransfear = MakeTransferOrder
FROM            SalesPersonsDevicePermissions
WHERE        (CompanyID = @CompNo)  AND (PositionsID = @PositionsID)  --     (CompanyID = @CompNo) AND (MakeOrderTaking = 1) AND (MakeSalesInvoice = 0) AND (PositionsID = @PositionsID)


IF @ClientActive= 11 and @SalesmanNo<>34 --and @IsMakeTransfear =1
BEGIN 

--if  @SalesmanNo in (1,2,3)
--BEGIN
--DELETE FROM [OSFA_DB]..[OT_StoreItemsQty_Main] where CompNo=@CompNo and SalesmanNo=@SalesmanNo
--INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty_Main]
--           ([CompNo]
--           ,[SalesmanNo]
--           ,[StoreNo]
--           ,[ItemNo]
--           ,[Qty])
  
--   select @CompNo,@SalesmanNo, 999999,ItemCode, sum (Qty)  from Olives_BO..StoresBalances
--   where Olives_BO..StoresBalances.StoreNo
--   in ('01','012','017','018','019','020','03','04','025') 
--   Group by ItemCode
--   End
--   else 

   

--BEGIN
--DELETE FROM [OSFA_DB]..[OT_StoreItemsQty_Main] where CompNo=@CompNo and SalesmanNo=@SalesmanNo
--INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty_Main]
--           ([CompNo]
--           ,[SalesmanNo]
--           ,[StoreNo]
--           ,[ItemNo]
--           ,[Qty])
  
--   select @CompNo,@SalesmanNo, 999999,ItemCode, sum (Qty)  from Olives_BO..StoresBalances
--   where Olives_BO..StoresBalances.StoreNo
--   in ('01','012','017','018','019','020','03','04','025') 
--   Group by ItemCode
--   End


	declare @mainStoreID nvarchar (500)

	select @mainStoreID=ForeignName from Olives_BO..SalesPersons where CompanyID=@CompNo and ID=@SalesmanNo

IF @CompNo=1
BEGIN

--if @SalesmanNo in(1,2)
--begin
--DELETE FROM [OSFA_DB]..[OT_StoreItemsQty_Main] where CompNo=@CompNo and SalesmanNo=@SalesmanNo
--INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty_Main]
--           ([CompNo]
--           ,[SalesmanNo]
--           ,[StoreNo]
--           ,[ItemNo]
--           ,[Qty])
  
--   select @CompNo,@SalesmanNo, 999999,ItemCode, sum (Qty)  from Olives_BO..StoresBalances
--   where Olives_BO..StoresBalances.StoreNo
--   in ('01','012','017','018','019','020','03','04','025') 
--   Group by ItemCode
--   End
--   else 

--   Begin
--DELETE FROM [OSFA_DB]..[OT_StoreItemsQty_Main] where CompNo=@CompNo and SalesmanNo=@SalesmanNo
--INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty_Main]
--           ([CompNo]
--           ,[SalesmanNo]
--           ,[StoreNo]
--           ,[ItemNo]
--           ,[Qty])
  
--   select @CompNo,@SalesmanNo, 999999,ItemCode, sum (Qty)  from Olives_BO..StoresBalancesz
--   where Olives_BO..StoresBalances.StoreNo
--   in ('01','012','017','018','019','020','03','04','025') 
--   Group by ItemCode
--   End






DELETE FROM [OSFA_DB]..[OT_StoreItemsQty_Main] where CompNo=@CompNo and SalesmanNo=@SalesmanNo
INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty_Main]
           ([CompNo]
           ,[SalesmanNo]
           ,[StoreNo]
           ,[ItemNo]
           ,[Qty])
  

    
SELECT        CompNo, SalesmanNo, StoreNo, ItemCode, sum(Qty)
FROM            (SELECT DISTINCT CompNo, SalesmanNo, StoreNo, ItemCode, Qty
                          FROM            (
						  SELECT        @CompNo AS CompNo, @SalesmanNo AS SalesmanNo, 999999 AS StoreNo, ItemCode, SUM(Qty) AS Qty
                                                    FROM            StoresBalances
                                                    WHERE        (StoreNo IN
                                                                                  (SELECT        stringPart
                                                                                    FROM            dbo.Fun_ConvArrayToTable(@mainStoreID, ',') AS t))
                                                    GROUP BY ItemCode) AS xbt
                          UNION ALL
                          SELECT        @CompNo AS Expr1, @SalesmanNo AS Expr2, 999999 AS Expr3, ItemNo, 0 AS Expr4
                          FROM            OSFA_DB.dbo.OT_ItemsMF AS OT_ItemsMF
                          WHERE        (SalesmanNo = @SalesmanNo) AND (CompNo = @CompNo)) AS tt

						  group by   CompNo, SalesmanNo, StoreNo, ItemCode
--   select @CompNo,@SalesmanNo, 999999,ItemCode, sum (Qty)  from Olives_BO..StoresBalances
--   where Olives_BO..StoresBalances.StoreNo
----   in ('01','012','017','018','019','020','03') 
--in ( SELECT t.stringPart FROM dbo.Fun_ConvArrayToTable(@mainStoreID,',') as t)
--   Group by ItemCode
   
 END
Else if @CompNo=3
Begin



--if @salesmanno in(1,2,3)
--Begin
-- DELETE FROM [OSFA_DB]..[OT_StoreItemsQty_Main] where CompNo=@CompNo and SalesmanNo=@SalesmanNo
-- INSERT INTO [OSFA_DB]..[OT_StoreItemsQty_Main]
--           ([CompNo]
--           ,[SalesmanNo]
--           ,[StoreNo]
--           ,[ItemNo]
--           ,[Qty])
  
--   select @CompNo,@SalesmanNo, 999999,ItemCode, sum (Qty)  from Olives_BO..StoresBalances
--   where Olives_BO..StoresBalances.StoreNo
--   in ('01','02','03','04','05','06','07','08','09','010','011','012','013') 
--   Group by ItemCode
--End
--else 
--Begin
-- DELETE FROM [OSFA_DB]..[OT_StoreItemsQty_Main] where CompNo=@CompNo and SalesmanNo=@SalesmanNo
-- INSERT INTO [OSFA_DB]..[OT_StoreItemsQty_Main]
--           ([CompNo]
--           ,[SalesmanNo]
--           ,[StoreNo]
--           ,[ItemNo]
--           ,[Qty])
  
--   select @CompNo,@SalesmanNo, 999999,ItemCode, sum (Qty)  from Olives_BO..StoresBalances
--   where Olives_BO..StoresBalances.StoreNo
--   in ('01','02','03','04','05','06','07','08','09','010','011','012','013') 
--   Group by ItemCode
--End

 DELETE FROM [OSFA_DB]..[OT_StoreItemsQty_Main] where CompNo=@CompNo and SalesmanNo=@SalesmanNo
 INSERT INTO [OSFA_DB]..[OT_StoreItemsQty_Main]
           ([CompNo]
           ,[SalesmanNo]
           ,[StoreNo]
           ,[ItemNo]
           ,[Qty])
  
   select @CompNo,@SalesmanNo, 999999,ItemCode, sum (Qty)  from Olives_BO..StoresBalances
   where Olives_BO..StoresBalances.StoreNo
--   in ('01','02','03','04','05','06','07','08','09','010','011','012','013') 
  in ( SELECT t.stringPart FROM dbo.Fun_ConvArrayToTable(@mainStoreID,',') as t)
   Group by ItemCode

End



 ELSE 

 BEGIN
 
 --if @SalesmanNo in (1,2,3)
 --begin
 -- DELETE FROM [OSFA_DB]..[OT_StoreItemsQty_Main] where CompNo=@CompNo and SalesmanNo=@SalesmanNo
 --INSERT INTO [OSFA_DB]..[OT_StoreItemsQty_Main]
 --          ([CompNo]
 --          ,[SalesmanNo]
 --          ,[StoreNo]
 --          ,[ItemNo]
 --          ,[Qty])
  
 --  select @CompNo,@SalesmanNo, 999999,ItemCode, sum (Qty)  from Olives_BO..StoresBalances
 --  where Olives_BO..StoresBalances.StoreNo
 --  in ('04','03','025' , '01' , '031', '028','020', '017') 
 --  Group by ItemCode
 --End
 --else

 --begin
 -- DELETE FROM [OSFA_DB]..[OT_StoreItemsQty_Main] where CompNo=@CompNo and SalesmanNo=@SalesmanNo
 --INSERT INTO [OSFA_DB]..[OT_StoreItemsQty_Main]
 --          ([CompNo]
 --          ,[SalesmanNo]
 --          ,[StoreNo]
 --          ,[ItemNo]
 --          ,[Qty])
  
 --  select @CompNo,@SalesmanNo, 999999,ItemCode, sum (Qty)  from Olives_BO..StoresBalances
 --  where Olives_BO..StoresBalances.StoreNo
 --  in ('04','03','025' , '01' , '031', '028','020', '017') 
 --  Group by ItemCode
 --End



 DELETE FROM [OSFA_DB]..[OT_StoreItemsQty_Main] where CompNo=@CompNo and SalesmanNo=@SalesmanNo
 INSERT INTO [OSFA_DB]..[OT_StoreItemsQty_Main]
           ([CompNo]
           ,[SalesmanNo]
           ,[StoreNo]
           ,[ItemNo]
           ,[Qty])
  
   select @CompNo,@SalesmanNo, 999999,ItemCode, sum (Qty)  from Olives_BO..StoresBalances
   where Olives_BO..StoresBalances.StoreNo
 --  in ('04','03','025' , '01' , '031', '028','020', '017') 
   in ( SELECT t.stringPart FROM dbo.Fun_ConvArrayToTable(@mainStoreID,',') as t)
   Group by ItemCode


   -- Oth555 Khobra Extra insert 26-5-2024
 INSERT INTO [OSFA_DB]..[OT_StoreItemsQty_Main]
           ([CompNo]
           ,[SalesmanNo]
           ,[StoreNo]
           ,[ItemNo]
           ,[Qty])

	SELECT        OSFA_DB.dbo.OT_ItemsMF.CompNo, @SalesmanNo AS Expr1,999999, OSFA_DB.dbo.OT_ItemsMF.ItemNo, OSFA_DB.dbo.OT_ItemsMF.QtyOH
	FROM            OSFA_DB.dbo.OT_ItemsMF LEFT OUTER JOIN
	                         OSFA_DB.dbo.OT_StoreItemsQty_Main ON OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = OSFA_DB.dbo.OT_StoreItemsQty_Main.SalesmanNo AND OSFA_DB.dbo.OT_ItemsMF.ItemNo = OSFA_DB.dbo.OT_StoreItemsQty_Main.ItemNo AND 
	                         OSFA_DB.dbo.OT_ItemsMF.CompNo = OSFA_DB.dbo.OT_StoreItemsQty_Main.CompNo
	WHERE        (OSFA_DB.dbo.OT_ItemsMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_StoreItemsQty_Main.CompNo IS NULL)


 END 
 END 
 

-- if @ClientActive= 69---Samah_Samah
-- Begin
 
--	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
--			   ([CompNo]
--			   ,[StoreNo]
--			   ,[ItemNo]
--			   ,[Qty])
--	SELECT        SalesPersonItemsBalance.CompanyID, SalesPersonItemsBalance.SalesPersonID, OT_ItemsMF.itemno, 
--                         SalesPersonItemsBalance.ItemQuantity
--	FROM            SalesPersonItemsBalance INNER JOIN
--							 OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsBalance.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
--							 SalesPersonItemsBalance.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND 
--							 SalesPersonItemsBalance.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
--	WHERE        (SalesPersonItemsBalance.CompanyID = @CompNo) AND (SalesPersonItemsBalance.SalesPersonID = @SalesmanNo)
--	/*SELECT     CompanyID, SalesPersonID, ItemCode, ItemQuantity
--	FROM         SalesPersonItemsBalance
--	WHERE     (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo)   */
--END

					   
	  
					  
																							 
											 
																 

-- IF @ClientActive = 21 
--BEGIN 
--print'Karadsheh Stock'
--delete from OSFA_DB.dbo.OT_StoreItemsQty_Main where CompNo=@CompNo and SalesmanNo=@SalesmanNo
--INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty_Main
--                         (CompNo, SalesmanNo,ItemNo, Qty,StoreNo)

														
												 
											 
			   

--SELECT     @CompNo,@SalesmanNo,ItemNo, sum (Qty), 999999
--FROM         ST_Karadsheh_CASHVAN.dbo.ItemBalance
--WHERE     (StoreID IN ('001-WHS', '002-WHS'))
--group by ItemNo

--END


IF @ClientActive = 29  
BEGIN 
print'xxxxx'
delete from OSFA_DB.dbo.OT_StoreItemsQty_Main where CompNo=@CompNo and SalesmanNo=@SalesmanNo
INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty_Main
                         (CompNo, SalesmanNo,ItemNo, Qty,StoreNo)

SELECT        OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, SUM(xxx.QtyOH) ,999999
                         AS QtyOH
FROM            DB.dbo.InvBatchsMF as xxx INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON xxx.CompNo = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
                         xxx.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo INNER JOIN
                         SalesPersons ON xxx.CompNo = SalesPersons.CompanyID AND xxx.StoreNo = SalesPersons.DeviceID AND 
                         OSFA_DB.dbo.OT_ItemsMF.CompNo = SalesPersons.CompanyID AND OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = SalesPersons.ID
WHERE        (xxx.CompNo = @CompNo) AND (xxx.IsHalt = 0) 
AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
GROUP BY OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, xxx.StoreNo
END






IF @ClientActive = 30
BEGIN 

--Declare @Ref2 smallint 
select  @Ref2 = SalesPersons.Reference2 from SalesPersons where ID =@SalesmanNo and CompanyID=@CompNo

IF @CompNo=1 and @Ref2=1
BEGIN 

delete from OSFA_DB.dbo.OT_StoreItemsQty_Main where CompNo=@CompNo and SalesmanNo=@SalesmanNo
INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty_Main
                         (CompNo, SalesmanNo,ItemNo, Qty,StoreNo)

SELECT        OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, SUM(DB.dbo.InvBatchsMF.QtyOH) AS Expr1, 999999 AS QtyOH
FROM            DB.dbo.InvBatchsMF INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON DB.dbo.InvBatchsMF.CompNo = OSFA_DB.dbo.OT_ItemsMF.CompNo AND DB.dbo.InvBatchsMF.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo
WHERE        (DB.dbo.InvBatchsMF.CompNo = @CompNo) AND (DB.dbo.InvBatchsMF.IsHalt = 0) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
and    DB.dbo.InvBatchsMF.StoreNo in (1,11,12,13,14,15,16,17)
GROUP BY OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo


END 
ELSE
Begin
delete from OSFA_DB.dbo.OT_StoreItemsQty_Main where CompNo=@CompNo and SalesmanNo=@SalesmanNo
INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty_Main
                         (CompNo, SalesmanNo,ItemNo, Qty,StoreNo)

SELECT        OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, SUM(DB.dbo.InvBatchsMF.QtyOH) ,999999
                         AS QtyOH
FROM            DB.dbo.InvBatchsMF INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON DB.dbo.InvBatchsMF.CompNo = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
                         DB.dbo.InvBatchsMF.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo INNER JOIN
                         SalesPersons ON DB.dbo.InvBatchsMF.CompNo = SalesPersons.CompanyID AND DB.dbo.InvBatchsMF.StoreNo = SalesPersons.Reference2 AND 
                         OSFA_DB.dbo.OT_ItemsMF.CompNo = SalesPersons.CompanyID AND OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = SalesPersons.ID
WHERE        (DB.dbo.InvBatchsMF.CompNo = @CompNo) AND (DB.dbo.InvBatchsMF.IsHalt = 0) AND 
                         (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
GROUP BY OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, DB.dbo.InvBatchsMF.StoreNo
END




------delete from OSFA_DB.dbo.OT_StoreItemsQty_Main where CompNo=@CompNo and SalesmanNo=@SalesmanNo
------INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty_Main
------                         (CompNo, SalesmanNo,ItemNo, Qty,StoreNo)

------SELECT        OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, SUM(DB.dbo.InvBatchsMF.QtyOH) ,999999
------                         AS QtyOH
------FROM            DB.dbo.InvBatchsMF INNER JOIN
------                         OSFA_DB.dbo.OT_ItemsMF ON DB.dbo.InvBatchsMF.CompNo = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
------                         DB.dbo.InvBatchsMF.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo INNER JOIN
------                         SalesPersons ON DB.dbo.InvBatchsMF.CompNo = SalesPersons.CompanyID AND DB.dbo.InvBatchsMF.StoreNo = SalesPersons.Reference2 AND 
------                         OSFA_DB.dbo.OT_ItemsMF.CompNo = SalesPersons.CompanyID AND OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = SalesPersons.ID
------WHERE        (DB.dbo.InvBatchsMF.CompNo = @CompNo) AND (DB.dbo.InvBatchsMF.IsHalt = 0) AND 
------                         (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
------GROUP BY OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, DB.dbo.InvBatchsMF.StoreNo
END
/* ---////Important//// uncomitt after update for Shokr Neam 
Else IF @ClientActive = 75  
BEGIN 

Delete from OSFA_DB.dbo.OT_StoreItemsQty_Main where CompNo=@CompNo and SalesmanNo=@SalesmanNo
INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty_Main
                         (CompNo, SalesmanNo, ItemNo, Qty, StoreNo)
SELECT        @CompNo AS Expr1, @SalesmanNo AS Expr2, ITEMNO, ISNULL(QTY,0), 999999 AS Expr3
FROM            SN..VAN2019.VW_ITEM_STOCK VW_ITEM_STOCK RIGHT OUTER JOIN
                         SalesPersonItemsAssignment ON VW_ITEM_STOCK.ItemNo = SalesPersonItemsAssignment.ItemCode
WHERE        (SalesPersonItemsAssignment.CompanyID = @CompNo) AND   (STOREID = 10) 
AND (SalesPersonItemsAssignment.PositionsID = @PositionsID)

END
*/
if @ClientActive = 17
begin
	exec GP_Integ_GetItemBalance @CompNo,@SalesmanNo
end

IF @ClientActive = 5
BEGIN
	DECLARE @AllowOrder bit
	SET @AllowOrder = 0
	SELECT       @AllowOrder = MakeOrderTaking
	FROM            SalesPersonsDevicePermissions
	WHERE        (CompanyID = @CompNo) AND (PositionsID = @PositionsID)
	--SELECT @AllowOrder = AllowOrder FROM [OSFA_DB].[dbo].[OT_SalesmanMF] WHERE(CompNo = CompNo) AND (SalesmanNo = @SalesmanNo)
	IF @AllowOrder = 1
	BEGIN
		DECLARE @CCC int
		SELECT @CCC = COUNT(1) FROM [OSFA_DB].[dbo].[OT_StoreItemsQty]
		WHERE (CompNo = CompNo) AND (StoreNo = @SalesmanNo)
		IF @CCC = 0
		BEGIN
			INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty] (CompNo, StoreNo, ItemNo, Qty)
			SELECT CompNo, SalesmanNo, ItemNo, QtyOH
			FROM [OSFA_DB].[dbo].[OT_ItemsMF]
			WHERE (CompNo = CompNo) AND (SalesmanNo = @SalesmanNo)
		END
	END
END

IF @ClientActive=24 -----ÑíÊßæ 
BEGIN

   	SELECT       @IsMakeOrder=  MakeOrderTaking
FROM            Olives_BO..SalesPersonsDevicePermissions
WHERE        (CompanyID = @CompNo ) AND (MakeOrderTaking = 1) AND (MakeSalesInvoice = 0) 
AND (PositionsID = (select PositionID from Olives_BO..SalesPersons where id=@SalesmanNo and CompanyID=@CompNo))


select @IsMakeOrder as IsMakeOrderssss
 if @IsMakeOrder=1
 Begin
SELECT @StoreID = Reference2 FROM olives_bo.dbo.SalesPersons WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo)
end
else
Begin
set @StoreID='002'
end

select @StoreID
delete  from OSFA_DB.DBO.OT_StoreItemsQty_Main where CompNo=@CompNo and  SalesmanNo=@SalesmanNo  
INSERT INTO OSFA_DB.DBO.OT_StoreItemsQty_Main
                         (CompNo, SalesmanNo, StoreNo, ItemNo, Qty)

																				 
				   

select CompNo,SalesmanNo,store,itemno,isnull (xbt.Qty * isnull (xbt.ConvertRate,1),0) from (
select @CompNo as CompNo ,@SalesmanNo as SalesmanNo,999999 as store,itemno,QTY , ROW_NUMBER() OVER(PARTITION BY itemno ORDER BY ConvertRate desc)  as cc,Olives_BO.dbo.ItemsUnitsDetails.ConvertRate

 from SAP_Integration.dbo.ItemBalance  LEFT OUTER JOIN
                         Olives_BO.dbo.ItemsUnitsDetails ON SAP_Integration.dbo.ItemBalance.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS = Olives_BO.dbo.ItemsUnitsDetails.ItemCode
where StoreID=@StoreID) as xbt
where xbt.cc=1


--select @CompNo,@SalesmanNo,999999,itemno,QTY

-- from SAP_Integration.dbo.ItemBalance
--where StoreID=@StoreID


END

IF @ClientActive = 78 and  @IsMakeOrder=1 

BEGIN 
DELETE from OSFA_DB.dbo.OT_StoreItemsQty where CompNo=@CompNo and StoreNo=@SalesmanNo

INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty
                      (CompNo, StoreNo, ItemNo, Qty)

select CompNo, SalesmanNo , ItemNo, QtyOH from OSFA_DB..OT_ItemsMF
where CompNo=@CompNo and SalesmanNo=@SalesmanNo
END 

IF @ClientActive=134
BEGIN 

select 0
--Delete from OSFA_DB.dbo.OT_StoreItemsQty where CompNo=@CompNo and StoreNo=@SalesmanNo

--INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty
--                         (CompNo, StoreNo, ItemNo, Qty)

--SELECT       @CompNo , @SalesmanNo ,  ItemCode, ISNULL (storeitem.store_onlineqty,0)
--FROM            [INTEG].[DataBaseAccSqlExport].[dbo].storeitem as storeitem RIGHT OUTER JOIN
--                         SalesPersonItemsAssignment ON storeitem.store_itemno COLLATE SQL_Latin1_General_CP1256_CI_AS = SalesPersonItemsAssignment.ItemCode
--WHERE        (SalesPersonItemsAssignment.CompanyID = @CompNo) AND (storeitem.store_no='1')AND storeitem.store_onlineqty>0 AND (SalesPersonItemsAssignment.PositionsID = @SalesmanNo)

END 
--IF @ClientActive=132
--BEGIN 


--Delete from OSFA_DB.dbo.OT_StoreItemsQty where CompNo=@CompNo and StoreNo=@SalesmanNo

--INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty
--                         (CompNo, StoreNo, ItemNo, Qty)

--SELECT       @CompNo , @SalesmanNo ,  ItemCode, ISNULL (storeitem.Qty,0)
----FROM               [ST_Shahid_CASHVAN].dbo.[ItemBalance] as storeitem RIGHT OUTER JOIN
--                         SalesPersonItemsAssignment ON storeitem.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS = SalesPersonItemsAssignment.ItemCode
--WHERE        (SalesPersonItemsAssignment.CompanyID = @CompNo)  and storeitem.UnitID<>'-1' and StoreID='Main' AND
--(SalesPersonItemsAssignment.PositionsID = @SalesmanNo)

--END 
IF @ClientActive=176
BEGIN 
Delete from OSFA_DB.dbo.OT_StoreItemsQty where CompNo=@CompNo and StoreNo=@SalesmanNo
select  @Ref2 = isnull (SalesPersons.Reference2,'0') from SalesPersons where ID =@SalesmanNo and CompanyID=@CompNo
INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty
                         (CompNo, StoreNo, ItemNo, Qty)


SELECT        @CompNo AS Expr1, @SalesmanNo AS Expr2, SalesPersonItemsAssignment.ItemCode, ISNULL(CitMultiStore.dbo.WHStock_V.Quantity, 0) AS Expr3
FROM            SalesPersons INNER JOIN
                         SalesPersonItemsAssignment ON SalesPersons.PositionID = SalesPersonItemsAssignment.PositionsID AND SalesPersons.CompanyID = SalesPersonItemsAssignment.CompanyID INNER JOIN
                         CitMultiStore.dbo.WHStock_V ON SalesPersons.Reference2 = CitMultiStore.dbo.WHStock_V.StoreNo AND 
                         SalesPersonItemsAssignment.ItemCode = CitMultiStore.dbo.WHStock_V.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS
WHERE        (SalesPersonItemsAssignment.CompanyID = @CompNo) AND (CitMultiStore.dbo.WHStock_V.StoreNo = @Ref2) AND (SalesPersonItemsAssignment.PositionsID = @SalesmanNo)
END


IF @ClientActive=178
BEGIN 


Delete from OSFA_DB.dbo.OT_StoreItemsQty where CompNo=@CompNo and StoreNo=@SalesmanNo
  
select  @Ref2 = isnull (SalesPersons.Reference2,'0') from SalesPersons where ID =@SalesmanNo and CompanyID=@CompNo

INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty
                         (CompNo, StoreNo, ItemNo, Qty)

SELECT        @CompNo AS Expr1, @SalesmanNo AS Expr2, SalesPersonItemsAssignment.ItemCode, ISNULL(CitMultiStore.dbo.WHStock_V.Quantity, 0) AS Expr3
FROM            SalesPersons INNER JOIN
                         SalesPersonItemsAssignment ON SalesPersons.PositionID = SalesPersonItemsAssignment.PositionsID AND SalesPersons.CompanyID = SalesPersonItemsAssignment.CompanyID INNER JOIN
                         CitMultiStore.dbo.WHStock_V ON SalesPersons.Reference2 = CitMultiStore.dbo.WHStock_V.StoreNo AND 
                         SalesPersonItemsAssignment.ItemCode = CitMultiStore.dbo.WHStock_V.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS
WHERE        (SalesPersonItemsAssignment.CompanyID = @CompNo) AND (CitMultiStore.dbo.WHStock_V.StoreNo = @Ref2) AND (SalesPersonItemsAssignment.PositionsID = @SalesmanNo)
END 



IF @ClientActive=68 and @SalesmanNo=55
BEGIN 


Delete from OSFA_DB.dbo.OT_StoreItemsQty where CompNo=@CompNo and StoreNo=@SalesmanNo

INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty
                         (CompNo, StoreNo, ItemNo, Qty)

SELECT       @CompNo , @SalesmanNo ,  ItemCode, ISNULL (CitMultiStore.dbo.WHStock_V.Quantity,0)
FROM            CitMultiStore.dbo.WHStock_V RIGHT OUTER JOIN
                         SalesPersonItemsAssignment ON CitMultiStore.dbo.WHStock_V.ItemNo COLLATE SQL_Latin1_General_CP1256_CI_AS = SalesPersonItemsAssignment.ItemCode
WHERE        (SalesPersonItemsAssignment.CompanyID = 1) AND (CitMultiStore.dbo.WHStock_V.StoreNo = @CompNo) AND (SalesPersonItemsAssignment.PositionsID = @SalesmanNo)
END 



IF @ClientActive=64 
BEGIN 


Delete from OSFA_DB.dbo.OT_StoreItemsQty where CompNo=@CompNo and StoreNo=@SalesmanNo

INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty
                         (CompNo, StoreNo, ItemNo, Qty)

SELECT        OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, SUM(DB.dbo.InvBatchsMF.QtyOH) AS Expr1
FROM            DB.dbo.InvBatchsMF INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON DB.dbo.InvBatchsMF.CompNo = OSFA_DB.dbo.OT_ItemsMF.CompNo AND DB.dbo.InvBatchsMF.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo
WHERE        (DB.dbo.InvBatchsMF.CompNo = @CompNo) AND (DB.dbo.InvBatchsMF.IsHalt = 0) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
and    DB.dbo.InvBatchsMF.StoreNo in (1)
GROUP BY OSFA_DB.dbo.OT_ItemsMF.CompNo, OSFA_DB.dbo.OT_ItemsMF.ItemNo, OSFA_DB.dbo.OT_ItemsMF.SalesmanNo


END 






SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_StoreItemsQty, OT_StoreItemsQty_Main [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
                      
----------------------------------

-- - CUSTOMER Statement --------
SET @BeginTime = Convert(varchar(20),GetDate(),108)

IF @ClientActive = 8 -- Saftey Food
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_StateAccBalance]
		   ([CompNo]
		   ,[SalesmanNo]
		   ,[CustomerNo]
		   ,[TrType]
		   ,[TrNo]
		   ,[TrSer]
		   ,[TrName]
		   ,[TrDate]
		   ,[Debit]
		   ,[Credit]
		   ,[Notes]
		   ,[Balance])
	SELECT        CustomerStatmentOfAccount.CompanyID, @SalesmanNo AS Expr1, CustomerStatmentOfAccount.CustomerID, CustomerStatmentOfAccount.TrType, 
							 CustomerStatmentOfAccount.TrNo, 
							  CASE WHEN CustomerStatmentOfAccount.TrNo = 999999999 then ((CustomerStatmentOfAccount.DeptNo)*1000) + 999 else
						 CASE WHEN CustomerStatmentOfAccount.TrNo = 0 then (CustomerStatmentOfAccount.DeptNo)*-1 else
						  CustomerStatmentOfAccount.TrSer end end,
							  CustomerStatmentOfAccount.TrName, CustomerStatmentOfAccount.TrDate, 
							 CustomerStatmentOfAccount.Debit, CustomerStatmentOfAccount.Credit, CustomerStatmentOfAccount.Notes, CustomerStatmentOfAccount.Balance
	FROM            CustomerStatmentOfAccount INNER JOIN
							 Alpha_Integration.dbo.SalesmanDeptLink ON CustomerStatmentOfAccount.DeptNo = Alpha_Integration.dbo.SalesmanDeptLink.DeptNo AND 
							 CustomerStatmentOfAccount.CompanyID = Alpha_Integration.dbo.SalesmanDeptLink.CompNo
	WHERE        (CustomerStatmentOfAccount.CompanyID = @CompNo) AND (CustomerStatmentOfAccount.CustomerID IN
								 (SELECT        CustomerNo
									FROM            OSFA_DB.dbo.OT_CustomerMF
									WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo))) AND (Alpha_Integration.dbo.SalesmanDeptLink.SalesmanNo = @SalesmanNo)
END

if @ClientActive=169 or @ClientActive=170
Begin

SELECT @PositionsID = PositionID FROM SALESPERSONS  WHERE CompanyID=@CompNo AND ID=@SalesmanNo

INSERT INTO [OSFA_DB].[dbo].[OT_StateAccBalance]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[TrType]
			   ,[TrNo]
			   ,[TrSer]
			   ,[TrName]
			   ,[TrDate]
			   ,[Debit]
			   ,[Credit]
			  -- ,[Notes]
			   ,[Balance]
			   )


SELECT CompanyID, @SalesmanNo,CustomerID,TransactionTypeID, TransactionNo, TrSerial, TrTypeName,TransactionDate, round(TrDebitAmount,3) TrDebitAmount, round(TrCreditAmount,3) TrCreditAmount ,    round (SUM(TrDebitAmount + (TrCreditAmount*-1) ) over (Partition by CustomerID Order BY TrSerial),3) AS Balance 
FROM     (
				  
				  SELECT @CompNo CompanyID, 999 AS TransactionTypeID, 2024 AS TransactionYear, 999  AS TransactionNo, 0 AS TrSerial, '2024-01-01' TransactionDate, CustomerID, 'رصيد افتتاحي' TrTypeName,  ISNULL (Customers.Balance,0) TrDebitAmount, 0  TrCreditAmount
FROM     Customers INNER JOIN
                  CustomersFinancialDetails ON Customers.CompanyID = CustomersFinancialDetails.CompanyID AND Customers.ID = CustomersFinancialDetails.CustomerID
				  WHERE CustomersFinancialDetails.CompanyID = @CompNo AND PositionsID=@PositionsID

				  UNION ALL
				  SELECT  CompanyID, TransactionTypeID, TransactionYear, TransactionNo, row_number() over (partition by  customerid order by customerid ) AS TrSerial, TransactionDate, CustomerID, TrTypeName, TrDebitAmount, TrCreditAmount
                  FROM      dbo.Fun_GetSalesmanStatmentOfAccount(@CompNo, @SalesmanNo)   )

             
                   AS OthTbl
				   

				   END

else if @ClientActive=144
Begin
	INSERT INTO [OSFA_DB].[dbo].[OT_StateAccBalance]
		   ([CompNo]
		   ,[SalesmanNo]
		   ,[CustomerNo]
		   ,[TrType]
		   ,[TrNo]
		   ,[TrSer]
		   ,[TrName]
		   ,[TrDate]
		   ,[Debit]
		   ,[Credit]
		   ,[Notes]
		   ,[Balance])
		   
	SELECT        CustomerStatmentOfAccount.CompanyID, @SalesmanNo AS Expr1, CustomerStatmentOfAccount.CustomerID,year( CustomerStatmentOfAccount.TrDate), 
							 CustomerStatmentOfAccount.TrNo, 
							  CASE WHEN CustomerStatmentOfAccount.TrNo = 9999 then 
							  9999 else
						 CASE WHEN CustomerStatmentOfAccount.TrNo = 0 then 0 else
						  CustomerStatmentOfAccount.TrSer end end,
							  CustomerStatmentOfAccount.TrName, CustomerStatmentOfAccount.TrDate, 
							 CustomerStatmentOfAccount.Debit, CustomerStatmentOfAccount.Credit, CustomerStatmentOfAccount.Notes, CustomerStatmentOfAccount.Balance
	FROM            CustomerStatmentOfAccount INNER JOIN
							Alpha_Integration.dbo.SalesmanDeptLink  SalesmanDeptLink ON CustomerStatmentOfAccount.DeptNo = SalesmanDeptLink.DeptNo AND 
							 CustomerStatmentOfAccount.CompanyID = SalesmanDeptLink.CompNo
		WHERE        (CustomerStatmentOfAccount.CompanyID = @CompNo) AND (CustomerStatmentOfAccount.CustomerID IN
								 (SELECT        CustomerNo
									FROM            OSFA_DB.dbo.OT_CustomerMF
									WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo))) 
									AND (SalesmanDeptLink.SalesmanNo = @SalesmanNo)

End



else IF  @ClientActive=149 
BEGIN
select 0
-- Remove the comment after update bec/ LinkedServer

	--INSERT INTO [OSFA_DB].[dbo].[OT_StateAccBalance]
	--	   ([CompNo]
	--	   ,[SalesmanNo]
	--	   ,[CustomerNo]
	--	   ,[TrType]
	--	   ,[TrNo]
	--	   ,[TrSer]
	--	   ,[TrName]
	--	   ,[TrDate]
	--	   ,[Debit]
	--	   ,[Credit]
	--	   ,[Notes]
	--	   ,[Balance])
	--SELECT        CustomerStatmentOfAccount.CompanyID, @SalesmanNo AS Expr1, CustomerStatmentOfAccount.CustomerID, CustomerStatmentOfAccount.TrType, 
	--						 CustomerStatmentOfAccount.TrNo, 
	--						  CASE WHEN CustomerStatmentOfAccount.TrNo = 999999999 then ((CustomerStatmentOfAccount.DeptNo)*100) + 9 else
	--					 CASE WHEN CustomerStatmentOfAccount.TrNo = 0 then (CustomerStatmentOfAccount.DeptNo)*-1 else
	--					  CustomerStatmentOfAccount.TrSer end end,
	--						  CustomerStatmentOfAccount.TrName, CustomerStatmentOfAccount.TrDate, 
	--						 CustomerStatmentOfAccount.Debit, CustomerStatmentOfAccount.Credit, CustomerStatmentOfAccount.Notes, CustomerStatmentOfAccount.Balance
	--FROM            CustomerStatmentOfAccount INNER JOIN
	--						 [10.5.5.52].Alpha_Integration.dbo.SalesmanDeptLink  SalesmanDeptLink ON CustomerStatmentOfAccount.DeptNo = SalesmanDeptLink.DeptNo AND 
	--						 CustomerStatmentOfAccount.CompanyID = SalesmanDeptLink.CompNo
	--	WHERE        (CustomerStatmentOfAccount.CompanyID = @CompNo) AND (CustomerStatmentOfAccount.CustomerID IN
	--							 (SELECT        CustomerNo
	--								FROM            OSFA_DB.dbo.OT_CustomerMF
	--								WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo))) AND (SalesmanDeptLink.SalesmanNo = @SalesmanNo)
END


else  if @ClientActive =27
Begin

Declare @CashCust_1 as varchar(max)
SELECT  @CashCust_1 = Op_Value FROM  OSFA_DB.dbo.OT_SystemOptions WHERE (CompNo = @CompNo) AND (Op_ID = 226) AND (SalesmanNo=0)


	INSERT INTO [OSFA_DB].[dbo].[OT_StateAccBalance]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[TrType]
			   ,[TrNo]
			   ,[TrSer]
			   ,[TrName]
			   ,[TrDate]
			   ,[Debit]
			   ,[Credit]
			   ,[Notes]
			   ,[Balance])
	SELECT     CompanyID, @SalesmanNo, CustomerID, TrType, TrNo, TrSer, TrName, TrDate, Debit, Credit, CustomerStatmentOfAccount.Notes, Balance
	FROM         CustomerStatmentOfAccount INNER JOIN [OSFA_DB].[dbo].[OT_CustomerMF] AS j ON
					CustomerStatmentOfAccount.CompanyID = j.CompNo AND
					CustomerStatmentOfAccount.CustomerID = j.CustomerNo
					LEFT OUTER JOIN [dbo].[Fun_ConvArrayToTable](@CashCust_1,',') AS i ON CustomerStatmentOfAccount.CustomerID = i.stringPart
	WHERE CompanyID = @CompNo AND (j.SalesmanNo = @SalesmanNo) AND (i.stringPart IS NULL) 
    
   
 
END


ELSE if @ClientActive=95 --and @SalesmanNo=10
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_StateAccBalance]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[TrType]
			   ,[TrNo]
			   ,[TrSer]
			   ,[TrName]
			   ,[TrDate]
			   ,[Debit]
			   ,[Credit]
			   ,[Notes]
			   ,[Balance])
	SELECT     CompanyID, @SalesmanNo, CustomerID, TrType, TrNo, TrSer, TrName, TrDate, Debit, Credit, Notes, Balance
	FROM         CustomerStatmentOfAccount
	WHERE CompanyID = @CompNo AND CustomerID IN(SELECT [CustomerNo] FROM [OSFA_DB].[dbo].[OT_CustomerMF] 
	WHERE (CompNo=@CompNo) AND (SalesmanNo = @SalesmanNo))
END    



else if @ClientActive=13
Begin


IF ISNULL (@IsMakeInvoice,0) <> 1
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_StateAccBalance]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]

			   ,[TrType]
			   ,[TrNo]
			   ,[TrSer]
			   ,[TrName]
			   ,[TrDate]
			   ,[Debit]
			   ,[Credit]
			   ,[Notes]
			   ,[Balance])
		SELECT     Customers.CompanyID, @SalesmanNo, CustomerID, TrType, TrNo, TrSer, TrName, TrDate, Debit, Credit,CustomerStatmentOfAccount.Notes, CustomerStatmentOfAccount.Balance
	FROM          CustomerStatmentOfAccount
	inner join customers on CustomerStatmentOfAccount.CompanyID=Customers.companyid and CustomerStatmentOfAccount.CustomerID=customers.id
	WHERE customers.CompanyID = @CompNo AND CustomerID IN(SELECT [CustomerNo] FROM [OSFA_DB].[dbo].[OT_CustomerMF] 
	WHERE (CompNo=@CompNo) AND (SalesmanNo = @SalesmanNo)and @salesmanno NOT IN (95,97,96,98,104,108))
	and (customers.Erp_Reference is Not NULL)

union all


	SELECT     Customers.CompanyID, @SalesmanNo, CustomerID, TrType, TrNo, TrSer, TrName, TrDate, Debit, Credit,CustomerStatmentOfAccount.Notes, CustomerStatmentOfAccount.Balance
	FROM          CustomerStatmentOfAccount
	inner join customers on CustomerStatmentOfAccount.CompanyID=Customers.companyid and CustomerStatmentOfAccount.CustomerID=customers.id
	WHERE customers.CompanyID = @CompNo AND CustomerID IN(SELECT [CustomerNo] FROM [OSFA_DB].[dbo].[OT_CustomerMF] 
	WHERE (CompNo=@CompNo) AND (SalesmanNo = @SalesmanNo)and @salesmanno NOT IN (95,97,96,98,104,108))
	and  (customers.Erp_Reference is NULL)
END 
END


 
ELSE if @ClientActive=142
BEGIN
exec [dbo].[Wings_Integ_Send_StatmentOfAccountBySalesman]  @CompNo,@SalesmanNo
END 
 
ELSE if @ClientActive=161
BEGIN
exec [dbo].[OT_Send_StatmentOfAccount_Client161]  @CompNo,@SalesmanNo,@SendDate
END 
ELSE
BEGIN
select 'def'
	INSERT INTO [OSFA_DB].[dbo].[OT_StateAccBalance]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[TrType]
			   ,[TrNo]
			   ,[TrSer]
			   ,[TrName]
			   ,[TrDate]
			   ,[Debit]
			   ,[Credit]
			   ,[Notes]
			   ,[Balance])
	SELECT     CompanyID, @SalesmanNo, CustomerID, TrType, TrNo, TrSer, TrName, TrDate, Debit, Credit, Notes, Balance
	FROM         CustomerStatmentOfAccount
	WHERE CompanyID = @CompNo AND CustomerID IN(SELECT [CustomerNo] FROM [OSFA_DB].[dbo].[OT_CustomerMF] 
	WHERE (CompNo=@CompNo) AND (SalesmanNo = @SalesmanNo))
END     


SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_StateAccBalance [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

IF @ClientActive = 17
BEGIN 


delete from OSFA_DB.dbo.OT_StoreItemsQty_Main where CompNo=@CompNo and SalesmanNo=@SalesmanNo
INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty_Main
                         (CompNo, SalesmanNo,ItemNo, Qty,StoreNo)

select @CompNo,@SalesmanNo, ItemNo, 0,999999  from OSFA_DB..OT_ItemsMF
where CompNo=@CompNo and SalesmanNo=@SalesmanNo 

END 


---------------------------------------------------
IF @ClientActive = 17
BEGIN
	EXEC GP_Integration_Wadi_Collect @CompNo, @PositionsID
END

--	----==================================================================

SET @BeginTime = Convert(varchar(20),GetDate(),108)

DECLARE @table table (TrDateTime smalldatetime, WeekNo int, DayNo int)
DECLARE @Maintable table (CompNo int ,SalesmanNo int,PosID int,TrDateTime smalldatetime, WeekNo int, DayNo int)
DECLARE @Fintable table (CompNo int ,SalesmanNo int,PosID int,TrDateTime smalldatetime, WeekNo int, DayNo int,RouteID int)

DECLARE @FromRouteDate datetime 
DECLARE @ToRouteDate smalldatetime 

SET @FromRouteDate = @SendDate
IF @ClientActive = 27
BEGIN
	SET @ToRouteDate = DateAdd(DAY,6,@FromRouteDate)
END
ELSE
BEGIN
	SET @ToRouteDate = DateAdd(Month,1,@FromRouteDate)
END

WHILE @FromRouteDate <= @ToRouteDate
BEGIN
	INSERT INTO @table
	VALUES(@FromRouteDate,dbo.Fun_GetWeekNo(@FromRouteDate),DATEPART(dw, @FromRouteDate))

	SET @FromRouteDate = DateAdd(Day,1,@FromRouteDate)
END

DECLARE @tblSalesman Table(CompNo int, SalesmanNo int, PositionID int)

INSERT INTO @tblSalesman
SELECT        CompanyID, ID, PositionID
FROM            SalesPersons
WHERE        (CompanyID = @CompNo) AND (ID = @SalesmanNo) 

INSERT INTO @Maintable(TrDateTime, WeekNo, DayNo, CompNo, SalesmanNo, PosID)
SELECT * FROM @table,@tblSalesman


if @ClientActive = 74 
Begin

INSERT INTO @Fintable(TrDateTime, WeekNo, DayNo, CompNo, SalesmanNo, PosID, RouteID)
SELECT i.TrDateTime, i.WeekNo, i.DayNo, i.CompNo, i.SalesmanNo, i.PosID,
 RouteID AS RouteID
FROM @Maintable as i inner join SalespersonRouteByDate ON
	i.CompNo = SalespersonRouteByDate.CompanyID AND
	i.PosID = SalespersonRouteByDate.PositionID AND
	i.TrDateTime = SalespersonRouteByDate.Date 

	union all

SELECT i.TrDateTime, i.WeekNo, i.DayNo, i.CompNo, i.SalesmanNo, i.PosID,
 RouteID AS RouteID
FROM @Maintable as i inner join SalespersonRouteByDate ON
	i.CompNo = SalespersonRouteByDate.CompanyID AND
	i.PosID = SalespersonRouteByDate.PositionID AND
	i.TrDateTime = SalespersonRouteByDate.Date 

	union all

SELECT i.TrDateTime, i.WeekNo, i.DayNo, i.CompNo, i.SalesmanNo, i.PosID, CASE WeekNo WHEN 1 THEN Week1 WHEN 2 THEN Week2 WHEN 3 THEN Week3 WHEN 4 THEN Week4 ELSE 0 END AS RouteID
FROM @Maintable as i inner join SalesPersonsRoutes ON
	i.CompNo = SalesPersonsRoutes.CompanyID AND
	i.PosID = SalesPersonsRoutes.PositionsID AND
	i.DayNo = SalesPersonsRoutes.WeekDay

end

ELSE
BEGIN
INSERT INTO @Fintable(TrDateTime, WeekNo, DayNo, CompNo, SalesmanNo, PosID, RouteID)
SELECT i.TrDateTime, i.WeekNo, i.DayNo, i.CompNo, i.SalesmanNo, i.PosID, CASE WeekNo WHEN 1 THEN Week1 WHEN 2 THEN Week2 WHEN 3 THEN Week3 WHEN 4 THEN Week4 ELSE 0 END AS RouteID
FROM @Maintable as i inner join SalesPersonsRoutes ON
	i.CompNo = SalesPersonsRoutes.CompanyID AND
	i.PosID = SalesPersonsRoutes.PositionsID AND
	i.DayNo = SalesPersonsRoutes.WeekDay

END

--	if @ClientActive = 38 
--	Begin
--	INSERT INTO [OSFA_DB].[dbo].[OT_SalesmanRoute] ([CompNo],[SalesmanNo],[RouteID],[CustomerNo],[RouteDate],[VisitOrder],[Visited],[TodayRoute])			
--select Distinct i.CompNo, i.SalesmanNo, i.RouteID, CustomersFinancialDetails.CustomerID, i.TrDateTime, ISNULL(Active.Sort,ROW_NUMBER() over (order by dbo.OT_GetLastTransDate (i.CompNo,CustomersFinancialDetails.CustomerID,1))) ,0,0
--from @Fintable as i Inner Join CustomersFinancialDetails ON
--	i.CompNo = CustomersFinancialDetails.CompanyID AND
--	i.PosID = CustomersFinancialDetails.PositionsID AND
--	i.RouteID = CustomersFinancialDetails.RouteID inner join osfa_DB.dbo.OT_CustomerMF As OT_CustomerMF on
--	CustomersFinancialDetails.CompanyID = OT_CustomerMF.CompNo AND
--	CustomersFinancialDetails.CustomerID = OT_CustomerMF.CustomerNo AND
--	OT_CustomerMF.SalesmanNo = @SalesmanNo left outer join dbo.[Fun_GetActiveCustomers] (@CompNo) as Active on 
--	CustomersFinancialDetails.CompanyID =Active.CompanyID And
--	CustomersFinancialDetails.CustomerID =Active.CustomerID 
--	end
--	else
--	begin
INSERT INTO [OSFA_DB].[dbo].[OT_SalesmanRoute] ([CompNo],[SalesmanNo],[RouteID],[CustomerNo],[RouteDate],[VisitOrder],[Visited],[TodayRoute])			
select Distinct i.CompNo, i.SalesmanNo, i.RouteID, CustomersFinancialDetails.CustomerID, i.TrDateTime, ISNULL(CustomersFinancialDetails.VisitOrder, 0) ,0,0
from @Fintable as i Inner Join CustomersFinancialDetails ON
	i.CompNo = CustomersFinancialDetails.CompanyID AND
	i.PosID = CustomersFinancialDetails.PositionsID AND
	i.RouteID = CustomersFinancialDetails.RouteID inner join osfa_DB.dbo.OT_CustomerMF As OT_CustomerMF on
	CustomersFinancialDetails.CompanyID = OT_CustomerMF.CompNo AND
	CustomersFinancialDetails.CustomerID = OT_CustomerMF.CustomerNo AND
	OT_CustomerMF.SalesmanNo = @SalesmanNo
	--end
/*
declare @FromRouteDate smalldatetime
declare @ToRouteDate smalldatetime 

SET @FromRouteDate = @SendDate
SET @ToRouteDate = DateAdd(Month,1,@FromRouteDate)

WHILE @FromRouteDate <= @ToRouteDate
BEGIN
	SET @WeekNo = dbo.Fun_GetWeekNo(@FromRouteDate)
	SET @DayOfWeek = DATEPART(dw, @FromRouteDate)

	SELECT     @RouteID = CASE @WeekNo WHEN 1 THEN Week1 WHEN 2 THEN Week2 WHEN 3 THEN Week3 WHEN 4 THEN Week4 ELSE 0 END 
	FROM         SalesPersonsRoutes
	WHERE     (CompanyID = @CompNo) AND (PositionsID = @PositionsID) AND (WeekDay = @DayOfWeek) 

	IF NOT @RouteID is null
	BEGIN
		INSERT INTO [OSFA_DB].[dbo].[OT_SalesmanRoute] ([CompNo],[SalesmanNo],[RouteID],[CustomerNo],[RouteDate],[VisitOrder],[Visited],[TodayRoute])
		SELECT CompanyID, SalesmanNo, RouteID, CustomerID, @FromRouteDate as TDate, SUM(case when VisitOrder in(0,9999) then 0 else VisitOrder end) as VisitOrder, 0, 0
		FROM (
			SELECT DISTINCT 
								 CustomersFinancialDetails.CompanyID, @SalesmanNo AS SalesmanNo, CustomersFinancialDetails.RouteID, CustomersFinancialDetails.CustomerID, 
								 ISNULL(CustomersFinancialDetails.VisitOrder, 9999) AS VisitOrder, 0 AS Expr2, 0 AS Expr3
			FROM            OSFA_DB.dbo.OT_CustomerMF INNER JOIN
									 CustomersFinancialDetails INNER JOIN
									 SalesPersons ON CustomersFinancialDetails.CompanyID = SalesPersons.CompanyID AND 
									 CustomersFinancialDetails.PositionsID = SalesPersons.PositionID INNER JOIN
									 Customers ON CustomersFinancialDetails.CompanyID = Customers.CompanyID AND CustomersFinancialDetails.CustomerID = Customers.ID ON 
									 OSFA_DB.dbo.OT_CustomerMF.CompNo = Customers.CompanyID AND OSFA_DB.dbo.OT_CustomerMF.CustomerNo = Customers.ID
			WHERE        (CustomersFinancialDetails.CompanyID = @CompNo) AND (CustomersFinancialDetails.PositionsID = @PositionsID) AND 
									 (CustomersFinancialDetails.RouteID = @RouteID) AND (SalesPersons.ID = @SalesmanNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
			) as xtbl
		Group by CompanyID, SalesmanNo, RouteID, CustomerID
	END
	SET @FromRouteDate = DateAdd(Day,1,@FromRouteDate)
END
*/
SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_SalesmanRoute [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

--	----==================================================================
/*
SELECT     @RouteID = CASE @WeekNo WHEN 1 THEN Week1 WHEN 2 THEN Week2 WHEN 3 THEN Week3 WHEN 4 THEN Week4 ELSE 0 END 
FROM         SalesPersonsRoutes
WHERE     (CompanyID = @CompNo) AND (PositionsID = @PositionsID) AND (WeekDay = @DayOfWeek)   

IF @ClientActive <> 14
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_SalesmanRoute]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[RouteID]
			   ,[CustomerNo]
			   ,[RouteDate]
			   ,[VisitOrder]
			   ,[Visited]
			   ,[TodayRoute])
	SELECT CompanyID, SalesmanNo, RouteID, CustomerID, Dt, SUM(case when VisitOrder in(0,9999) then 0 else VisitOrder end) as VisitOrder, 0, 0
	FROM (
		SELECT DISTINCT 
								 CustomersFinancialDetails.CompanyID, @SalesmanNo AS SalesmanNo, CustomersFinancialDetails.RouteID, CustomersFinancialDetails.CustomerID, 
								 @SendDate AS Dt, ISNULL(CustomersFinancialDetails.VisitOrder, 9999) AS VisitOrder, 0 AS Expr2, 0 AS Expr3
		FROM            OSFA_DB.dbo.OT_CustomerMF INNER JOIN
								 CustomersFinancialDetails INNER JOIN
								 SalesPersons ON CustomersFinancialDetails.CompanyID = SalesPersons.CompanyID AND 
								 CustomersFinancialDetails.PositionsID = SalesPersons.PositionID INNER JOIN
								 Customers ON CustomersFinancialDetails.CompanyID = Customers.CompanyID AND CustomersFinancialDetails.CustomerID = Customers.ID ON 
								 OSFA_DB.dbo.OT_CustomerMF.CompNo = Customers.CompanyID AND OSFA_DB.dbo.OT_CustomerMF.CustomerNo = Customers.ID
		WHERE        (CustomersFinancialDetails.CompanyID = @CompNo) AND (CustomersFinancialDetails.PositionsID = @PositionsID) AND 
								 (CustomersFinancialDetails.RouteID = @RouteID) AND (SalesPersons.ID = @SalesmanNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
	) as xtbl
	Group by CompanyID, SalesmanNo, RouteID, CustomerID, Dt
	--SELECT    distinct CustomersFinancialDetails.CompanyID, @SalesmanNo AS Expr4, CustomersFinancialDetails.RouteID, CustomersFinancialDetails.CustomerID, @SendDate AS Dt, 
	--					  IsNUll(CustomersFinancialDetails.VisitOrder,9999) AS Expr1, 0 AS Expr2, 0 AS Expr3
	--FROM         CustomersFinancialDetails INNER JOIN
	--					  SalesPersons ON CustomersFinancialDetails.CompanyID = SalesPersons.CompanyID AND CustomersFinancialDetails.PositionsID = SalesPersons.PositionID
	--WHERE     (CustomersFinancialDetails.CompanyID = @CompNo) AND (CustomersFinancialDetails.PositionsID = @PositionsID) AND 
	--					  (CustomersFinancialDetails.RouteID = @RouteID) AND (SalesPersons.ID = @SalesmanNo)
END
ELSE
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_SalesmanRoute]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[RouteID]
			   ,[CustomerNo]
			   ,[RouteDate]
			   ,[VisitOrder]
			   ,[Visited]
			   ,[TodayRoute])
	SELECT CompanyID, SalesmanNo, RouteID, CustomerID, Dt, SUM(case when VisitOrder in(0,9999) then 0 else VisitOrder end) as VisitOrder, 0, 0
	FROM (
		SELECT DISTINCT 
                         CustomersFinancialDetails.CompanyID, @SalesmanNo AS SalesmanNo, CustomersFinancialDetails.RouteID, CustomersFinancialDetails.CustomerID, 
                         @SendDate AS Dt, ISNULL(CustomersFinancialDetails.VisitOrder, 9999) AS VisitOrder, 0 AS Expr2, 0 AS Expr3
		FROM            OSFA_DB.dbo.OT_CustomerMF INNER JOIN
								 CustomersFinancialDetails INNER JOIN
								 SalesPersons ON CustomersFinancialDetails.CompanyID = SalesPersons.CompanyID AND 
								 CustomersFinancialDetails.PositionsID = SalesPersons.PositionID INNER JOIN
								 Customers ON CustomersFinancialDetails.CompanyID = Customers.CompanyID AND CustomersFinancialDetails.CustomerID = Customers.ID ON 
								 OSFA_DB.dbo.OT_CustomerMF.CompNo = CustomersFinancialDetails.CompanyID AND 
								 OSFA_DB.dbo.OT_CustomerMF.CustomerNo = CustomersFinancialDetails.CustomerID
		WHERE        (CustomersFinancialDetails.CompanyID = @CompNo) AND (CustomersFinancialDetails.PositionsID = @PositionsID) AND 
								 (CustomersFinancialDetails.RouteID = @RouteID) AND (SalesPersons.ID = @SalesmanNo) AND (ISNULL(Customers.IsSuspended, 0) = 0) AND 
								 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
	) as xtbl
	Group by CompanyID, SalesmanNo, RouteID, CustomerID, Dt

	--SELECT DISTINCT 
 --                        CustomersFinancialDetails.CompanyID, @SalesmanNo AS Expr4, CustomersFinancialDetails.RouteID, CustomersFinancialDetails.CustomerID, @SendDate AS Dt, 
 --                        IsNUll(CustomersFinancialDetails.VisitOrder,9999) AS Expr1, 0 AS Expr2, 0 AS Expr3
	--FROM            CustomersFinancialDetails INNER JOIN
 --                        SalesPersons ON CustomersFinancialDetails.CompanyID = SalesPersons.CompanyID AND 
 --                        CustomersFinancialDetails.PositionsID = SalesPersons.PositionID INNER JOIN
 --                        Customers ON CustomersFinancialDetails.CompanyID = Customers.CompanyID AND CustomersFinancialDetails.CustomerID = Customers.ID
	--WHERE        (CustomersFinancialDetails.CompanyID = @CompNo) AND (CustomersFinancialDetails.PositionsID = @PositionsID) AND 
 --                        (CustomersFinancialDetails.RouteID = @RouteID) AND (SalesPersons.ID = @SalesmanNo) AND (IsNull(Customers.IsSuspended,0) = 0)
END
              */        
-------------------------
     
-- - CUSTOMER DRAWERS --------
SET @BeginTime = Convert(varchar(20),GetDate(),108)

IF  @ClientActive <> 37 or @ClientActive <>30
BEGIN 
INSERT INTO [OSFA_DB].[dbo].[OT_Drawers]
           ([CompNo]
           ,[SalesmanNo]
           ,[Customer_No]
           ,[DrawerID]
           ,[DrawerName])
SELECT     CompanyID, @SalesmanNo , CustomerID, ID, Name
FROM         Drawers
WHERE     (CompanyID = @CompNo) AND (CustomerID IN
                          (SELECT     CustomerNo
                             FROM         OSFA_DB.dbo.OT_CustomerMF
                             WHERE     (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)))  and ISNULL(IsSuspended,0)=0
							 END  
IF  @ClientActive  =30
BEGIN
delete from   [OSFA_DB].[dbo].[OT_Drawers] where  ([CompNo] = @CompNo) and [SalesmanNo] = @SalesmanNo
INSERT INTO [OSFA_DB].[dbo].[OT_Drawers]
           ([CompNo]
           ,[SalesmanNo]
           ,[Customer_No]
           ,[DrawerID]
           ,[DrawerName])
SELECT     CompanyID, @SalesmanNo , CustomerID, ID, Name
FROM         Drawers
WHERE     (CompanyID = @CompNo) AND (CustomerID IN
                          (SELECT     CustomerNo
                             FROM         OSFA_DB.dbo.OT_CustomerMF
                             WHERE     (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)))  and  ISNULL(IsSuspended,0)<>1
							 END  
  -- - CreditInvoiceList --------
 
 IF @ClientActive = 18
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_CreditInvoiceList]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[InvType]
			   ,[InvYear]
			   ,[InvNo]

			   ,[InvoiceAmount]
			   ,[InvoiceRemainingAmount]
			   ,[InvoiceDueDate]
			   ,[InvoiceDate]
			   ,[InvoiceAge])
	SELECT        x.CompanyID, @SalesmanNo, CustomerID, x.PaidTransTypeID, x.PaidTransYear, x.PaidTransNo, PaidTransAmount, SUM(x.PaidTransRemainingAmount) AS PaidTransRemainingAmount,
					PaidTransDueDate, PaidTransDate, datediff(day,PaidTransDate,getdate())
	FROM            (SELECT        CompanyID, PaidTransTypeID, PaidTransYear, PaidTransNo, PaidTransRemainingAmount, 0 AS PaidAmount
							   FROM            CustomersPaidTransList
							   WHERE        (CompanyID = @CompNo)
							   UNION ALL
							   SELECT        CompanyID, PaidTransTypeID, PaidTransYear, PaidTransNo, 0 AS Expr1, SUM(PaidAmount) AS PaidAmount
							   FROM            Receipts_PaidTrans
							   WHERE        (CompanyID = @CompNo) AND (PostedToERP IS NULL)
							   GROUP BY CompanyID, PaidTransYear, PaidTransNo, PaidTransTypeID) AS x INNER JOIN
							 CustomersPaidTransList AS CustomersPaidTransList_1 ON x.CompanyID = CustomersPaidTransList_1.CompanyID AND 
							 x.PaidTransTypeID = CustomersPaidTransList_1.PaidTransTypeID AND x.PaidTransYear = CustomersPaidTransList_1.PaidTransYear AND 
							 x.PaidTransNo = CustomersPaidTransList_1.PaidTransNo
	WHERE (CustomerID IN (SELECT        CustomerNo
						  FROM            OSFA_DB.dbo.OT_CustomerMF
						  WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)))  
	GROUP BY x.CompanyID, x.PaidTransYear, x.PaidTransNo, x.PaidTransTypeID,
	CustomerID,PaidTransAmount,PaidTransDueDate, PaidTransDate
	HAVING        (SUM(x.PaidTransRemainingAmount) - SUM(x.PaidAmount) > 0) 
END
ELSE  IF @ClientActive = 17
BEGIN
	if @SalesmanGroupID=10000
	begin
		INSERT INTO [OSFA_DB].[dbo].[OT_CreditInvoiceList]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[InvType]
			   ,[InvYear]
			   ,[InvNo]
			   ,[InvoiceAmount]
			   ,[InvoiceRemainingAmount]
			   ,[InvoiceDueDate]
			   ,[InvoiceDate]
			   ,[InvoiceAge]
			   ,[Ref1])
		SELECT     @CompNo AS CompanyID,  @SalesmanNo, Customers.ID, GP_Integration.dbo.UnAppliedINV.Document_Type,
				GP_Integration.dbo.GpTrxToCdsTrx.TrxYear, GP_Integration.dbo.GpTrxToCdsTrx.TrNo,
		GP_Integration.dbo.UnAppliedINV.Document_Amount,
						GP_Integration.dbo.UnAppliedINV.Unapplied_Amount,
						   GP_Integration.dbo.UnAppliedINV.Document_Date, 
						  GP_Integration.dbo.UnAppliedINV.Document_Date,
						  datediff(day,GP_Integration.dbo.UnAppliedINV.Document_Date,getdate()),
						  GP_Integration.dbo.GpTrxToCdsTrx.RefTrxNo
		FROM         GP_Integration.dbo.UnAppliedINV INNER JOIN
							  Customers ON GP_Integration.dbo.UnAppliedINV.Customer_ID = Customers.Reference1 COLLATE Arabic_CI_AS INNER JOIN
							  GP_Integration.dbo.GpTrxToCdsTrx ON GP_Integration.dbo.UnAppliedINV.Document_Number = GP_Integration.dbo.GpTrxToCdsTrx.RefTrxNo AND 
							  GP_Integration.dbo.UnAppliedINV.Document_Type = GP_Integration.dbo.GpTrxToCdsTrx.RefTrxType
		WHERE (Customers.ID IN
									 (SELECT        CustomerNo
										FROM            OSFA_DB.dbo.OT_CustomerMF
										WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)))  
										and GP_Integration.dbo.UnAppliedINV.Document_Date=convert(date,getdate())
	end
	else
	begin
		INSERT INTO [OSFA_DB].[dbo].[OT_CreditInvoiceList]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[InvType]
			   ,[InvYear]
			   ,[InvNo]
			   ,[InvoiceAmount]
			   ,[InvoiceRemainingAmount]
			   ,[InvoiceDueDate]
			   ,[InvoiceDate]
			   ,[InvoiceAge]
			   ,[Ref1]
			   )
		SELECT     @CompNo AS CompanyID,  @SalesmanNo, Customers.ID, GP_Integration.dbo.UnAppliedINV.Document_Type,
				GP_Integration.dbo.GpTrxToCdsTrx.TrxYear, GP_Integration.dbo.GpTrxToCdsTrx.TrNo,
		GP_Integration.dbo.UnAppliedINV.Document_Amount,
						GP_Integration.dbo.UnAppliedINV.Unapplied_Amount,
						   GP_Integration.dbo.UnAppliedINV.Document_Date, 
						  GP_Integration.dbo.UnAppliedINV.Document_Date,
						  datediff(day,GP_Integration.dbo.UnAppliedINV.Document_Date,getdate()),
						  GP_Integration.dbo.GpTrxToCdsTrx.RefTrxNo
		FROM         GP_Integration.dbo.UnAppliedINV INNER JOIN
							  Customers ON GP_Integration.dbo.UnAppliedINV.Customer_ID = Customers.Reference1 COLLATE Arabic_CI_AS INNER JOIN
							  GP_Integration.dbo.GpTrxToCdsTrx ON GP_Integration.dbo.UnAppliedINV.Document_Number = GP_Integration.dbo.GpTrxToCdsTrx.RefTrxNo AND 
							  GP_Integration.dbo.UnAppliedINV.Document_Type = GP_Integration.dbo.GpTrxToCdsTrx.RefTrxType
		WHERE (Customers.ID IN
									 (SELECT        CustomerNo
										FROM            OSFA_DB.dbo.OT_CustomerMF
										WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)))                        		   
	end                      		 
END
ELSE IF @ClientActive = 24 AND @CompNo = 2 -- ÑíÊßæ 
BEGIN
	INSERT INTO OSFA_DB.dbo.OT_CreditInvoiceList (CompNo, SalesmanNo, CustomerNo, InvType, InvYear, InvNo, InvoiceAmount, InvoiceRemainingAmount, InvoiceDueDate, InvoiceDate, InvoiceAge)
	SELECT        @CompNo AS Expr1, @SalesmanNo AS Expr2, Customers.ID AS CustomerID, 1 AS Expr3, YEAR(OutstandingInvoices.InvoiceDate) AS Expr4, OutstandingInvoices.InvoiceNo, OutstandingInvoices.InvoiceAmount, 
							 OutstandingInvoices.InvoiceRemainingAmount, OutstandingInvoices.InvoiceDueDate, OutstandingInvoices.InvoiceDate, DATEDIFF(day, OutstandingInvoices.InvoiceDate, GETDATE()) AS Expr5
	FROM            SAP_Integration.dbo.OutstandingInvoices AS OutstandingInvoices INNER JOIN
							 Customers ON OutstandingInvoices.CustomerID = Customers.Reference1 collate SQL_Latin1_General_CP1256_CI_AS INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON Customers.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND Customers.ID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (Customers.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
END


--ELSE IF @ClientActive = 90 AND @CompNo = 1  
--BEGIN

--INSERT INTO OSFA_DB.dbo.OT_CreditInvoiceList
--                         (CompNo, SalesmanNo, CustomerNo, InvType, InvYear, InvNo, InvoiceAmount, InvoiceRemainingAmount, InvoiceDueDate, InvoiceDate, InvoiceAge)


--SELECT       @compno,@SalesmanNo,Customers.ID,1 as InvType,year(getdate()) as InvYear,cast(@SalesmanNo as nvarchar(50))+cast((ROW_NUMBER() OVER(PARTITION BY @SalesmanNo ORDER BY @SalesmanNo DESC)) as nvarchar(500))as InvNo,
--Round(Customers.CustomerBalance,2),Round(Customers.CustomerBalance,2),cast(GETDATE()-1 as date) as InvoiceDueDate,cast(GETDATE()-1 as date) as InvoiceDate,0 as InvoiceAge
--FROM            Customers INNER JOIN
--                         CustomersFinancialDetails ON Customers.CompanyID = CustomersFinancialDetails.CompanyID AND Customers.ID = CustomersFinancialDetails.CustomerID INNER JOIN
--                         SalesPersons ON CustomersFinancialDetails.CompanyID = SalesPersons.CompanyID AND CustomersFinancialDetails.PositionsID = SalesPersons.PositionID
--WHERE         (Customers.CompanyID = @compno) and SalesPersons.id=@SalesmanNo


--END

ELSE IF @ClientActive = 80 -- ÍãæÏÉ
BEGIN
	INSERT INTO OSFA_DB.dbo.OT_CreditInvoiceList (CompNo, SalesmanNo, CustomerNo, InvType, InvYear, InvNo, InvoiceAmount, InvoiceRemainingAmount, InvoiceDueDate, InvoiceDate, InvoiceAge)
	SELECT        @CompNo AS Expr1, @SalesmanNo AS Expr2, Customers.ID AS CustomerID, 1 AS Expr3, YEAR(OutstandingInvoices.NextDueDate) AS Expr4, '1' , OutstandingInvoices.Balance, 
							 OutstandingInvoices.Balance, OutstandingInvoices.NextDueDate , OutstandingInvoices.NextDueDate , DATEDIFF(day, OutstandingInvoices.NextDueDate, GETDATE()) AS Expr5
	FROM           ST_JPPMC_CASH_VAN1.dbo.customermaster AS OutstandingInvoices INNER JOIN
							 Customers ON OutstandingInvoices.ID = Customers.Reference1 INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON Customers.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND Customers.ID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (Customers.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (OutstandingInvoices.NextDueDate > '1899-12-30 00:00:00.000')
END

ELSE IF @ClientActive =51
BEGIN
delete from [OSFA_DB]..[OT_CreditInvoiceList] where [CompNo]=@CompNo and [SalesmanNo]=@SalesmanNo
INSERT INTO [OSFA_DB]..[OT_CreditInvoiceList]
           ([CompNo]
           ,[SalesmanNo]
           ,[CustomerNo]
           ,[InvType]
           ,[InvYear]
           ,[InvNo]
           ,[InvoiceAmount]
           ,[InvoiceRemainingAmount]
           ,[InvoiceDueDate]
           ,[InvoiceDate]
      )

 SELECT        @CompNo AS CompNo, OT_CustomerMF.SalesmanNo,CustomerNo,1, YEAR(SAP_Integration.dbo.OutstandingInvoices.InvoiceDate) , SAP_Integration.dbo.OutstandingInvoices.InvoiceNo,
                         SAP_Integration.dbo.OutstandingInvoices.InvoiceAmount, SAP_Integration.dbo.OutstandingInvoices.InvoiceRemainingAmount, SAP_Integration.dbo.OutstandingInvoices.InvoiceDueDate, 
                         SAP_Integration.dbo.OutstandingInvoices.InvoiceDate
FROM            SAP_Integration.dbo.OutstandingInvoices INNER JOIN
                        OSFA_DB..OT_CustomerMF ON SAP_Integration.dbo.OutstandingInvoices.CustomerID = OT_CustomerMF.CustomerRef1 collate SQL_Latin1_General_CP1256_CI_AS
WHERE        (OT_CustomerMF.CompNo = @CompNo) and OT_CustomerMF.SalesmanNo=@SalesmanNo

END 


ELSE IF @ClientActive = 5 --السهم الذهبي
BEGIN
 INSERT INTO [OSFA_DB].[dbo].[OT_CreditInvoiceList]
           ([CompNo]
           ,[SalesmanNo]
           ,[CustomerNo]
           ,[InvType]
           ,[InvYear]
           ,[InvNo]
           ,[InvoiceAmount]
           ,[InvoiceRemainingAmount]
           ,[InvoiceDueDate]
		   ,[InvoiceDate]
		   ,[InvoiceAge]
		   ,Ref1
		   ,Ref2
		   ,Ref3
		   ,Ref4)
SELECT        CompanyID, @SalesmanNo AS Expr1, CustomerID, PaidTransTypeID, PaidTransYear, PaidTransNo, PaidTransAmount, PaidTransRemainingAmount, 
                         PaidTransDueDate, PaidTransDate, datediff(day,PaidTransDate,getdate()),
						 Ref1,Ref2,Ref3,Ref4 
FROM            CustomersPaidTransList
WHERE        (CompanyID = @CompNo) AND PaidTransRemainingAmount >0.99 and (CustomerID IN
                             (SELECT        CustomerNo
                                FROM            OSFA_DB.dbo.OT_CustomerMF
                                WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) and (Customerno not in (5343,4258,4296, 124,125,146,147,155,156,163,164,441,442,849,850,1907,1908,2095,2096,2253,2254,
2446,2447,2457,2458,2462,2463,2465,2466,2467,2469,2470,2471,2472,2473,2474,2475,2477,2478,2480,2481,2482,
2483,
2485,
2486,
2487,
2488,
2489,
2490,
2493,
2494,
2495,
2496,
2497,
2498,
2499,
2500,
2501,
2502,
2503,
2504,
2505,
2506,
2507,
2508,
2509,
2510,
2511,
2512,
2513,
2514,
2515,
2516,
2517,
2518,
2519,
2520,
2523,
2524,
2525,
2526,
2527,
2528,
2531,
2532,
2533,
2534,
2536,
2537,
2540,
2541,
2542,
2543,
2544,
2545,
2546,
2547,
2548,
2549,
2550,
2551,
2553,
2554,
2555,
2556,
2558,
2559,
2561,
2562,
2563,
2564,
2565,
2566,
2567,
2568,
2569,
2570,
2571,
2572,
2573,
2574,
2575,
2576,
2577,
2578,
2579,
2580,
2581,
2582,
4208,
4210,
4212,
4213,
4217,
4218,
4222,
4224,
4225,
4227,
4228,
4229,
4230,
4246,
4247,
4248,
4255,
4256,
4257,
4258,
4259,
4260,
4262,
4263,
4264,
4265,
4266,
4267,
4272,
4273,
4281,
4282,
4283,
4284,
4286,
4291,
4292,
4295,
4296,
4297,
4299,
4300,
4306,
4307,
4310,
4311,
4346,
4347,
4357,
4358,
4371,
4372,
5822,
5846,
5847,
5848,
6039,
6040,
7425,
7426,
7427,
7428,
7429,
7430,
7431,
7432,
7433,
7434,
7435,
7436,
7437,
7438,
7439,
7440,
7441,
7442,
7443,
7444,
7445,
7446,
7447,
7505,
7506,
7507,
7508,
7520,
7560,
7686,
7737,
7738,
7807,
7879,
7880,
7881,
7882,
7883,
8038,
8039,
8526,
10231,
10296,
10328,
10332,
10338,
10344,
10406,
12164,
12167,
12170,
12171,
12180,
12181,
12323,
12342,
12343,
12359,
12360,
12398,
12414,
12439,
12440,
12446,
12453,
12454,
12538,
12545,
12595,
12598,
12599,
12600,
12702,
12749,
12752,
12753,
12909,
13705,
13706,
13778,
13779,
13780,
13781,
13797,
13798,
13799,
13856,
13857,
13883,
13922,
13923,
13924,
13968,
13969,
14187,
14188,
14262,
14268,
14269,
14283,
14287,
14288,
14289,
14290,
14292,
14293,
14294,
14361,
14370,
14602,
14646,
14675,
14702,
14709,
14710,
14711,
14712,
14724,
14765,
14874,
15182,
15213,
15236,
15240,
15242,
15244,
15245,
15246,
15249,
15250,
15254,
15255,
15276,
15277,
15279,
15356,
15385,
15387,
15449,
15683,
15684,
15765,
15842,
15843,
15844,
15868,
15901,
15990,
16172,
16174,
16378,
16711,
16961,
17261,
17276,
17590,
17717,
17718,
17767,
17768,
17769,
18302,
18310,
18311,
18376,
18470,
18858,
19019,
19044,
19090,
19119,
19187,
19269,
19316,
19532,
19592,
19661,
19678,
19679,
19682,
19698
))))  and  PaidTransRemainingAmount > 0.10
END


ELSE IF @ClientActive =85

Begin

SELECT      @IsMakeInvoiceAndOrder=isnull (SalesPersonsDevicePermissions.MakeSalesInvoice,0)
FROM            SalesPersonsDevicePermissions INNER JOIN
                         SalesPersons ON SalesPersonsDevicePermissions.CompanyID = SalesPersons.CompanyID AND SalesPersonsDevicePermissions.PositionsID = SalesPersons.PositionID
WHERE        (SalesPersonsDevicePermissions.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo)  AND (SalesPersonsDevicePermissions.MakeSalesInvoice = 1)

print '@IsMakeInvoiceAndOrder'
print @IsMakeInvoiceAndOrder

delete from [OSFA_DB]..[OT_CreditInvoiceList] where [CompNo]=@CompNo and [SalesmanNo]=@SalesmanNo

if @IsMakeInvoiceAndOrder = 1
BEGIN
 INSERT INTO [OSFA_DB].[dbo].[OT_CreditInvoiceList]
           ([CompNo]
           ,[SalesmanNo]
           ,[CustomerNo]
           ,[InvType]
           ,[InvYear]
           ,[InvNo]
           ,[InvoiceAmount]
           ,[InvoiceRemainingAmount]
           ,[InvoiceDueDate]
		   ,[InvoiceDate]
		   ,[InvoiceAge]
		   ,Ref1
		   ,Ref2
		   ,Ref3
		   ,Ref4)
SELECT  distinct   CustomersPaidTransList.CompanyID, @SalesmanNo AS Expr1, CustomersPaidTransList.CustomerID, CustomersPaidTransList.PaidTransTypeID, CustomersPaidTransList.PaidTransYear, CustomersPaidTransList.PaidTransNo, 
                  CustomersPaidTransList.PaidTransAmount, CustomersPaidTransList.PaidTransRemainingAmount, CustomersPaidTransList.PaidTransDate + 35 AS Expr2, CustomersPaidTransList.PaidTransDate, DATEDIFF(day, CustomersPaidTransList.PaidTransDate, GETDATE()) 
                  AS Expr3, CustomersPaidTransList.Ref1, CustomersPaidTransList.Ref2, CustomersPaidTransList.Ref3, isnull (TransactionsHeaders.CustomerName ,'') as ref4
FROM        CustomersPaidTransList INNER JOIN
                  Customers ON CustomersPaidTransList.CompanyID = Customers.CompanyID AND CustomersPaidTransList.CustomerID = Customers.ID LEFT OUTER JOIN
                  TransactionsHeaders ON  cast (TransactionsHeaders.TransactionNo as nvarchar)= SUBSTRING(cast (CustomersPaidTransList.Ref5 as nvarchar), 3, LEN(CustomersPaidTransList.Ref5) )  AND CustomersPaidTransList.CompanyID = TransactionsHeaders.CompanyID  AND CustomersPaidTransList.PaidTransYear = TransactionsHeaders.TransactionYear  LEFT OUTER JOIN
                  dbo.Fun_GetMaxCustomerTypeEarlyPayDays(@CompNo) AS Fun_GetMaxCustomerTypeEarlyPayDays ON Customers.CompanyID = Fun_GetMaxCustomerTypeEarlyPayDays.CompanyID AND 
                  Customers.TypeID = Fun_GetMaxCustomerTypeEarlyPayDays.CustomerTypeID
WHERE     (CustomersPaidTransList.CompanyID = @CompNo) AND (CustomersPaidTransList.CustomerID IN
                      (SELECT     CustomerNo
                       FROM        OSFA_DB.dbo.OT_CustomerMF
                       WHERE     (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo))) 
								

end
else
BEGIN
 INSERT INTO [OSFA_DB].[dbo].[OT_CreditInvoiceList]
           ([CompNo]
           ,[SalesmanNo]
           ,[CustomerNo]
           ,[InvType]
           ,[InvYear]
           ,[InvNo]
           ,[InvoiceAmount]
           ,[InvoiceRemainingAmount]
           ,[InvoiceDueDate]
		   ,[InvoiceDate]
		   ,[InvoiceAge]
		   ,Ref1
		   ,Ref2
		   ,Ref3
		   ,Ref4)
SELECT        CustomersPaidTransList.CompanyID, @SalesmanNo AS Expr1, CustomerID, PaidTransTypeID, PaidTransYear, PaidTransNo, PaidTransAmount, PaidTransRemainingAmount, 
                          PaidTransDate+35  , PaidTransDate, datediff(day,PaidTransDate,getdate()),
						 Ref1,Ref2,Ref3,Ref4 
FROM            CustomersPaidTransList INNER JOIN Customers ON CustomersPaidTransList.CompanyID=Customers.CompanyID AND CustomersPaidTransList.CustomerID=Customers.ID LEFT OUTER JOIN [dbo].[Fun_GetMaxCustomerTypeEarlyPayDays](@CompNo) AS Fun_GetMaxCustomerTypeEarlyPayDays
ON Customers.CompanyID=Fun_GetMaxCustomerTypeEarlyPayDays.CompanyID AND Customers.TypeID= Fun_GetMaxCustomerTypeEarlyPayDays.CustomerTypeID
WHERE        (CustomersPaidTransList.CompanyID = @CompNo) AND (CustomersPaidTransList.CustomerID IN
                             (SELECT        CustomerNo
                                FROM            OSFA_DB.dbo.OT_CustomerMF
                                WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)))  
								

end

END


ELSE IF @ClientActive =8
BEGIN
 INSERT INTO [OSFA_DB].[dbo].[OT_CreditInvoiceList]
           ([CompNo]
           ,[SalesmanNo]
           ,[CustomerNo]
           ,[InvType]
           ,[InvYear]
           ,[InvNo]
           ,[InvoiceAmount]
           ,[InvoiceRemainingAmount]
           ,[InvoiceDueDate]
		   ,[InvoiceDate]
		   ,[InvoiceAge]
		   ,Ref1
		   ,Ref2
		   ,Ref3
		   ,Ref4)
SELECT        CompanyID, @SalesmanNo AS Expr1, CustomerID, PaidTransTypeID, PaidTransYear, PaidTransNo, PaidTransAmount, PaidTransRemainingAmount, 
                          case when @ClientActive=85 then  PaidTransDate+39 else  cast(ISNULL(PaidTransDueDate,getdate()) as date) end ,cast( ISNULL(PaidTransDate,getdate()) as date),
						  datediff(day,isnull(PaidTransDate,getdate()),getdate()) ,
						 Ref1,Ref2,Ref3,Ref4 
FROM            CustomersPaidTransList
WHERE        (CompanyID = @CompNo) AND (CustomerID IN
                             (SELECT        CustomerNo
                                FROM            OSFA_DB.dbo.OT_CustomerMF
                                WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)))       and PaidTransRemainingAmount>1    
END

ELSE IF @ClientActive =144
BEGIN
 INSERT INTO [OSFA_DB].[dbo].[OT_CreditInvoiceList]
           ([CompNo]
           ,[SalesmanNo]
           ,[CustomerNo]
           ,[InvType]
           ,[InvYear]
           ,[InvNo]
           ,[InvoiceAmount]
           ,[InvoiceRemainingAmount]
           ,[InvoiceDueDate]
		   ,[InvoiceDate]
		   ,[InvoiceAge]
		   ,Ref1
		   ,Ref2
		   ,Ref3
		   ,Ref4)
SELECT        CompanyID, @SalesmanNo AS Expr1, CustomerID, PaidTransTypeID, PaidTransYear, PaidTransNo, PaidTransAmount, PaidTransRemainingAmount, 
                          case when @ClientActive=85 then  PaidTransDate+39 else  PaidTransDueDate end , PaidTransDate, datediff(day,PaidTransDate,getdate()),
						 Ref1,Ref2,Ref3,Ref4 
FROM            CustomersPaidTransList INNER JOIN
							Alpha_Integration.dbo.SalesmanDeptLink  SalesmanDeptLink ON
							 CustomersPaidTransList.ref3 = SalesmanDeptLink.DeptNo AND 
							 CustomersPaidTransList.CompanyID = SalesmanDeptLink.CompNo
WHERE        (CompanyID = @CompNo) AND (CustomerID IN
                             (SELECT        CustomerNo
                                FROM            OSFA_DB.dbo.OT_CustomerMF
                                WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)))     and 
                                SalesmanDeptLink.SalesmanNo      =@SalesmanNo
END




ELSE IF @ClientActive <> 30 and @ClientActive <>67
BEGIN
 INSERT INTO [OSFA_DB].[dbo].[OT_CreditInvoiceList]
           ([CompNo]
           ,[SalesmanNo]
           ,[CustomerNo]
           ,[InvType]
           ,[InvYear]
           ,[InvNo]
           ,[InvoiceAmount]
           ,[InvoiceRemainingAmount]
           ,[InvoiceDueDate]
		   ,[InvoiceDate]
		   ,[InvoiceAge]
		   ,Ref1
		   ,Ref2
		   ,Ref3
		   ,Ref4)
SELECT        CompanyID, @SalesmanNo AS Expr1, CustomerID, PaidTransTypeID, PaidTransYear, PaidTransNo, PaidTransAmount, PaidTransRemainingAmount, 
                          case when @ClientActive=85 then  PaidTransDate+39 else case when @ClientActive=32 then PaidTransDate+15 else  PaidTransDueDate end end , PaidTransDate, datediff(day,PaidTransDate,getdate()),
						 Ref1,Ref2,case when @ClientActive=165 then  SUM(PaidTransRemainingAmount) OVER (PARTITION BY CustomerID ORDER BY PaidTransNo,PaidTransDate) else Ref3 end as Ref3,Ref4 
FROM            CustomersPaidTransList
WHERE        (CompanyID = @CompNo) AND (CustomerID IN
                             (SELECT        CustomerNo
                                FROM            OSFA_DB.dbo.OT_CustomerMF
                                WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)))            
END
  
SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_Drawers, OT_CreditInvoiceList [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')


SET @BeginTime = Convert(varchar(20),GetDate(),108)

INSERT INTO OSFA_DB.dbo.OT_Contracts (CompNo, SalesmanNo, ContractID, ContractName, StartDate, EndDate, CustomerID)
SELECT        Contracts.CompanyID, SalesPersons.ID, Contracts.ContractID, Contracts.ContractName, Contracts.StartDate, Contracts.EndDate, Contracts.CustomerID
FROM            Contracts INNER JOIN
                         SalesPersonContractsAssignment ON Contracts.CompanyID = SalesPersonContractsAssignment.CompanyID AND 
                         Contracts.ContractID = SalesPersonContractsAssignment.ContractID INNER JOIN
                         SalesPersons ON SalesPersonContractsAssignment.CompanyID = SalesPersons.CompanyID AND 
                         SalesPersonContractsAssignment.PositionsID = SalesPersons.PositionID
WHERE        (Contracts.CompanyID = @CompNo) AND (ISNULL(Contracts.IsSuspended, 0) = 0) AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, Contracts.StartDate)) <= @SendDate) 
                         AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, Contracts.EndDate)) >= @SendDate) AND (SalesPersons.ID = @SalesmanNo)


INSERT INTO OSFA_DB.dbo.OT_ContractItems (CompNo, SalesmanNo, ContractID, ItemCode, UnitID, MaxQty, SalesQty)
SELECT        ContractItems.CompanyID, SalesPersons.ID, ContractItems.ContractID, ContractItems.ItemCode, ContractItems.UnitID, ContractItems.MaxQty, 0 AS Expr1
FROM            ContractItems INNER JOIN
                         OSFA_DB.dbo.OT_Contracts ON ContractItems.CompanyID = OSFA_DB.dbo.OT_Contracts.CompNo AND 
                         ContractItems.ContractID = OSFA_DB.dbo.OT_Contracts.ContractID INNER JOIN
                         SalesPersonContractsAssignment ON ContractItems.CompanyID = SalesPersonContractsAssignment.CompanyID AND 
                         ContractItems.ContractID = SalesPersonContractsAssignment.ContractID INNER JOIN
                         SalesPersons ON SalesPersonContractsAssignment.CompanyID = SalesPersons.CompanyID AND 
                         SalesPersonContractsAssignment.PositionsID = SalesPersons.PositionID
WHERE        (ContractItems.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo)

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_ContractItems [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

-- -- CustStockHistory -------- 
SET @BeginTime = Convert(varchar(20),GetDate(),108)

DECLARE @CurrYear int
SET @CurrYear=YEAR(@SendDate)


IF @ClientActive=85
BEGIN
DECLARE @DocTypeNo varchar(50) 
SET @DocTypeNo=[dbo].[Fun_GetSalesmanSysOpValue](@CompNo,@SalesmanNo,491)

IF @DocTypeNo<>'N/A' AND @DocTypeNo<>'0'
BEGIN
	DECLARE @Tbl_CustomerStock Table(CustomerID bigint,OrderDate smalldatetime,CategCode Varchar(500),SubCategCode Varchar(500)  primary key (CustomerID ,OrderDate ,CategCode ,SubCategCode))
	INSERT INTO @Tbl_CustomerStock
	SELECT   DISTINCT   TblH.CustomersID,TblH.OrderDate,
						  ISNULL(ItemsCategories.Parent, ItemsCategories.CategCode) AS CategCode, ItemsCategories.CategCode AS Subcateg
	FROM           CustomerStockTacking   AS TblH INNER JOIN
						  CustomerStockTackingDetails ON TblH.CompanyID = CustomerStockTackingDetails.CompanyID AND TblH.OrderYear = CustomerStockTackingDetails.OrderYear AND 
						  TblH.OrderNo = CustomerStockTackingDetails.OrderNo INNER JOIN
						  Items ON CustomerStockTackingDetails.CompanyID = Items.CompanyID AND CustomerStockTackingDetails.ItemCode = Items.ItemCode INNER JOIN
							 ItemsCategories ON Items.CompanyID = ItemsCategories.CompanyID AND Items.CategCode = ItemsCategories.CategCode INNER JOIN
							OSFA_DB..OT_CustomerMF AS OT_CustomerMF ON TblH.CustomersID = OT_CustomerMF.CustomerNo AND TblH.CompanyID = OT_CustomerMF.CompNo
	 WHERE (TblH.CompanyID = @CompNo) and OT_CustomerMF.SalesmanNo=@SalesmanNo AND TblH.DocumentTypeID=CAST(@DocTypeNo AS int)
	  Union All
	 SELECT   DISTINCT   TblH.CustomersID,TblH.OrderDate,
						  Items.ItemCode AS CategCode, Items.UnitID AS Subcateg
	FROM           CustomerStockTacking   AS TblH INNER JOIN
						  CustomerStockTackingDetails ON TblH.CompanyID = CustomerStockTackingDetails.CompanyID AND TblH.OrderYear = CustomerStockTackingDetails.OrderYear AND 
						  TblH.OrderNo = CustomerStockTackingDetails.OrderNo INNER JOIN
						  Items ON CustomerStockTackingDetails.CompanyID = Items.CompanyID AND CustomerStockTackingDetails.ItemCode = Items.ItemCode INNER JOIN
							 ItemsCategories ON Items.CompanyID = ItemsCategories.CompanyID AND Items.CategCode = ItemsCategories.CategCode INNER JOIN
							OSFA_DB..OT_CustomerMF AS OT_CustomerMF ON TblH.CustomersID = OT_CustomerMF.CustomerNo AND TblH.CompanyID = OT_CustomerMF.CompNo
	 WHERE (TblH.CompanyID = @CompNo) and OT_CustomerMF.SalesmanNo=@SalesmanNo AND TblH.DocumentTypeID=CAST(@DocTypeNo AS int)
	

	DECLARE @Tbl_SalesOrder Table(CustomerID bigint,OrderDate smalldatetime,CategCode Varchar(500),SubCategCode Varchar(500) primary key (CustomerID ,OrderDate ,CategCode ,SubCategCode))
	INSERT INTO @Tbl_SalesOrder
	SELECT     DISTINCT   OrdersHeaders.CustomerID, OrdersHeaders.OrderDate,
						  ISNULL(ItemsCategories.Parent, ItemsCategories.CategCode) AS CategCode, ItemsCategories.CategCode AS Subcateg
	FROM            OrdersHeaders INNER JOIN
							 OrdersDetails ON OrdersHeaders.CompanyID = OrdersDetails.CompanyID AND OrdersHeaders.OrderYear = OrdersDetails.OrderYear AND OrdersHeaders.OrderNo = OrdersDetails.OrderNo INNER JOIN
							 Items ON OrdersDetails.CompanyID = Items.CompanyID AND OrdersDetails.ItemCode = Items.ItemCode INNER JOIN
							 ItemsCategories ON Items.CompanyID = ItemsCategories.CompanyID AND Items.CategCode = ItemsCategories.CategCode  INNER JOIN
							OSFA_DB..OT_CustomerMF AS OT_CustomerMF ON OrdersHeaders.CustomerID = OT_CustomerMF.CustomerNo AND OrdersHeaders.CompanyID = OT_CustomerMF.CompNo
	 WHERE (OrdersHeaders.CompanyID = @CompNo) and OT_CustomerMF.SalesmanNo=@SalesmanNo
	  Union All 
	 SELECT     DISTINCT   OrdersHeaders.CustomerID, OrdersHeaders.OrderDate,
						  Items.ItemCode AS CategCode, Items.UnitID AS Subcateg
	FROM            OrdersHeaders INNER JOIN
							 OrdersDetails ON OrdersHeaders.CompanyID = OrdersDetails.CompanyID AND OrdersHeaders.OrderYear = OrdersDetails.OrderYear AND OrdersHeaders.OrderNo = OrdersDetails.OrderNo INNER JOIN
							 Items ON OrdersDetails.CompanyID = Items.CompanyID AND OrdersDetails.ItemCode = Items.ItemCode INNER JOIN
							 ItemsCategories ON Items.CompanyID = ItemsCategories.CompanyID AND Items.CategCode = ItemsCategories.CategCode  INNER JOIN
							OSFA_DB..OT_CustomerMF AS OT_CustomerMF ON OrdersHeaders.CustomerID = OT_CustomerMF.CustomerNo AND OrdersHeaders.CompanyID = OT_CustomerMF.CompNo
	 WHERE (OrdersHeaders.CompanyID = @CompNo) and OT_CustomerMF.SalesmanNo=@SalesmanNo


	INSERT INTO [OSFA_DB].[dbo].[OT_CustStockHistory]
				([CompNo]
				,[SalesmanNo]
				,[CustomerNo]
				,[ItemNo]
				,[UnitCode]
				,[Qty]
				,[ItemDesc])
 
 
	SELECT DISTINCT @CompNo,@SalesmanNo, Tbl_CustomerStock.CustomerID,Tbl_CustomerStock.CategCode,Tbl_CustomerStock.SubCategCode ,0,'' FROM @Tbl_CustomerStock AS Tbl_CustomerStock LEFT OUTER JOIN @Tbl_SalesOrder AS Tbl_SalesOrder ON 
	Tbl_CustomerStock.CustomerID=Tbl_SalesOrder.CustomerID    AND  
	Tbl_CustomerStock.CategCode=Tbl_SalesOrder.CategCode  AND  Tbl_CustomerStock.SubCategCode=Tbl_SalesOrder.SubCategCode
	AND Tbl_CustomerStock.OrderDate<=Tbl_SalesOrder.OrderDate
	WHERE Tbl_SalesOrder.OrderDate IS NULL

END
END
ELSE
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_CustStockHistory]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[ItemNo]
			   ,[UnitCode]
			   ,[Qty]
			   ,[ItemDesc])
	SELECT     TblH.CompanyID, TblH.SalesPersonID, TblH.CustomersID, CustomerStockTackingDetails.ItemCode, CustomerStockTackingDetails.UnitID,
						  [dbo].[GetItemOrgUnitQty](TblH.CompanyID,CustomerStockTackingDetails.ItemCode,CustomerStockTackingDetails.UnitID,CustomerStockTackingDetails.Quantity) AS Qty, Items.Name
	FROM         (SELECT     CompanyID, OrderYear, MAX(OrderNo) AS OrderNo, CustomersID, SalesPersonID
							FROM         CustomerStockTacking
							GROUP BY CompanyID, OrderYear, CustomersID, SalesPersonID
							HAVING      (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (OrderYear = @CurrYear)) AS TblH INNER JOIN
						  CustomerStockTackingDetails ON TblH.CompanyID = CustomerStockTackingDetails.CompanyID AND TblH.OrderYear = CustomerStockTackingDetails.OrderYear AND 
						  TblH.OrderNo = CustomerStockTackingDetails.OrderNo INNER JOIN
						  Items ON CustomerStockTackingDetails.CompanyID = Items.CompanyID AND CustomerStockTackingDetails.ItemCode = Items.ItemCode





END

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_CustStockHistory [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
                          
-- Suggest Order ------------------------------------------------------------
SET @BeginTime = Convert(varchar(20),GetDate(),108)

IF @ClientActive <> 1 AND @ClientActive <> 4 AND @ClientActive <> 27 AND @ClientActive <> 30 AND @ClientActive <> 0  and @ClientActive <> 136 and @clientactive <>69 and @ClientActive <> 67  and @ClientActive <> 50 and @ClientActive <> 128
BEGIN
	INSERT INTO OSFA_DB.dbo.OT_ItemsQtyAvg
							 (CompNo, SalesmanNo, CustomerNo, ItemNo, Avg_OrderQty, Avg_SalesQty, Avg_SalesRetQty)
	SELECT CompanyID,SalesPersonID,CustomerID,ItemCode, SUM(OrderQty) as OrderQty, SUM(SalesQty) as SalesQty, SUM(ReturnSalesQty) as ReturnSalesQty
	FROM(
	SELECT     OrdersHeaders.CompanyID, OrdersHeaders.SalesPersonID, OrdersHeaders.CustomerID, OrdersDetails.ItemCode, 
				dbo.GetItemOrgUnitQty(@CompNo, OrdersDetails.ItemCode, dbo.GetItemUnitBySerial(@CompNo, OrdersDetails.ItemCode, 3), CEILING(SUM(OrdersDetails.Quantity + OrdersDetails.Bonus) / COUNT(DISTINCT OrdersHeaders.OrderNo))) AS OrderQty, 0 AS SalesQty, 0 AS ReturnSalesQty
	FROM         OrdersHeaders INNER JOIN
						  OrdersDetails ON OrdersHeaders.CompanyID = OrdersDetails.CompanyID AND OrdersHeaders.OrderYear = OrdersDetails.OrderYear AND 
						  OrdersHeaders.OrderNo = OrdersDetails.OrderNo INNER JOIN
						  SalesPersonItemsAssignment ON OrdersDetails.CompanyID = SalesPersonItemsAssignment.CompanyID AND 
						  OrdersDetails.ItemCode = SalesPersonItemsAssignment.ItemCode
	WHERE     (OrdersHeaders.CompanyID = @CompNo) AND (OrdersHeaders.OrderDate BETWEEN @FromDate AND @SendDate)  
						   AND (OrdersHeaders.SalesPersonID = @SalesmanNo) AND (SalesPersonItemsAssignment.PositionsID = @PositionsID)					  

	GROUP BY OrdersHeaders.CompanyID, OrdersHeaders.SalesPersonID, OrdersHeaders.CustomerID, OrdersDetails.ItemCode

	Union ALL

	SELECT        TransactionsHeaders.CompanyID, TransactionsHeaders.SalesPersonID, TransactionsHeaders.CustomerID, TransactionsDetails.ItemCode, 0, 
				  ABS(dbo.GetItemOrgUnitQty(@CompNo, TransactionsDetails.ItemCode, dbo.GetItemUnitBySerial(@CompNo, TransactionsDetails.ItemCode, 3),  CEILING(SUM(CASE WHEN TransactionsHeaders.TransactionTypeID = 1 THEN TransactionsDetails.Quantity + TransactionsDetails.Bonus ELSE 0 END) / COUNT(DISTINCT TransactionsHeaders.TransactionNo)))) AS SalesQty,
				  ABS(dbo.GetItemOrgUnitQty(@CompNo, TransactionsDetails.ItemCode, dbo.GetItemUnitBySerial(@CompNo, TransactionsDetails.ItemCode, 3),  CEILING(SUM(CASE WHEN TransactionsHeaders.TransactionTypeID = 2 THEN TransactionsDetails.Quantity + TransactionsDetails.Bonus ELSE 0 END) / COUNT(DISTINCT TransactionsHeaders.TransactionNo)))) AS ReturnSalesQty
	FROM            TransactionsHeaders INNER JOIN
							 TransactionsDetails ON TransactionsHeaders.CompanyID = TransactionsDetails.CompanyID AND 
							 TransactionsHeaders.TransactionTypeID = TransactionsDetails.TransactionTypeID AND 
							 TransactionsHeaders.TransactionYear = TransactionsDetails.TransactionYear AND 
							 TransactionsHeaders.TransactionNo = TransactionsDetails.TransactionNo INNER JOIN
							 SalesPersonItemsAssignment ON TransactionsDetails.CompanyID = SalesPersonItemsAssignment.CompanyID AND 
							 TransactionsDetails.ItemCode = SalesPersonItemsAssignment.ItemCode
	WHERE        (TransactionsHeaders.CompanyID = @CompNo) AND (TransactionsHeaders.SalesPersonID = @SalesmanNo) AND (SalesPersonItemsAssignment.PositionsID = @PositionsID) AND 
							 (TransactionsHeaders.TransactionDate BETWEEN @FromDate AND @SendDate) AND (TransactionsHeaders.TransactionTypeID IN (1, 2))
	GROUP BY TransactionsHeaders.CompanyID, TransactionsHeaders.SalesPersonID, TransactionsHeaders.CustomerID, TransactionsDetails.ItemCode
	) as tblx
	Group By CompanyID,SalesPersonID,CustomerID,ItemCode
END

IF @ClientActive <> 4 AND @ClientActive <> 27 AND @ClientActive <> 30 AND @ClientActive <> 0 and @ClientActive <> 50 and @ClientActive <> 128
BEGIN
INSERT INTO OSFA_DB.dbo.OT_ItemsQtyAvg
                         (CompNo, SalesmanNo, CustomerNo, ItemNo, Avg_OrderQty, Avg_SalesQty, Avg_SalesRetQty)

SELECT   DISTINCT     ItemsPriority.CompanyID, @SalesmanNo AS Expr1, Customers.ID, ItemsPriority.ItemCode, dbo.GetItemSmallUnitQty(@CompNo, ItemsPriority.ItemCode, ItemsPriority.UnitID, ItemsPriority.Qty) AS Expr2, 
                         0 AS Expr3, 0 AS Expr4
FROM            ItemsPriority INNER JOIN
                         Customers ON ItemsPriority.CompanyID = Customers.CompanyID AND ISNULL(ItemsPriority.CustTypeID,Customers.TypeID) = Customers.TypeID INNER JOIN
                         SalesPersonItemsAssignment ON ItemsPriority.CompanyID = SalesPersonItemsAssignment.CompanyID AND ItemsPriority.ItemCode = SalesPersonItemsAssignment.ItemCode LEFT OUTER JOIN
                         OSFA_DB.dbo.OT_ItemsQtyAvg ON Customers.ID = OSFA_DB.dbo.OT_ItemsQtyAvg.CustomerNo AND ItemsPriority.CompanyID = OSFA_DB.dbo.OT_ItemsQtyAvg.CompNo AND 
                         ItemsPriority.ItemCode = OSFA_DB.dbo.OT_ItemsQtyAvg.ItemNo AND OSFA_DB.dbo.OT_ItemsQtyAvg.SalesmanNo = @SalesmanNo
WHERE        (OSFA_DB.dbo.OT_ItemsQtyAvg.CompNo IS NULL) AND (ItemsPriority.CompanyID = @CompNo) AND (ISNULL(ItemsPriority.UseInSuggestedOrder, 0) = 1) AND (Customers.ID IN
                             (SELECT        CustomerNo
                                FROM            OSFA_DB.dbo.OT_CustomerMF
                                WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo))) AND (SalesPersonItemsAssignment.PositionsID = @PositionsID)

END

if @ClientActive =128

Begin

INSERT INTO OSFA_DB.dbo.OT_ItemsQtyAvg
                         (CompNo, SalesmanNo, CustomerNo, ItemNo, Avg_OrderQty, Avg_SalesQty, Avg_SalesRetQty)

SELECT   DISTINCT     ItemsPriority.CompanyID, @SalesmanNo AS Expr1, Customers.ID, ItemsPriority.ItemCode, dbo.GetItemSmallUnitQty(@CompNo, ItemsPriority.ItemCode, ItemsPriority.UnitID, ItemsPriority.Qty) AS Expr2,
                         0 AS Expr3, 0 AS Expr4
FROM            ItemsPriority INNER JOIN
                         Customers ON ItemsPriority.CompanyID = Customers.CompanyID AND ISNULL(ItemsPriority.CustTypeID,Customers.TypeID) = Customers.TypeID INNER JOIN
                         SalesPersonItemsAssignment ON ItemsPriority.CompanyID = SalesPersonItemsAssignment.CompanyID AND ItemsPriority.ItemCode = SalesPersonItemsAssignment.ItemCode LEFT OUTER JOIN
                         OSFA_DB.dbo.OT_ItemsQtyAvg ON Customers.ID = OSFA_DB.dbo.OT_ItemsQtyAvg.CustomerNo AND ItemsPriority.CompanyID = OSFA_DB.dbo.OT_ItemsQtyAvg.CompNo AND
                         ItemsPriority.ItemCode = OSFA_DB.dbo.OT_ItemsQtyAvg.ItemNo AND OSFA_DB.dbo.OT_ItemsQtyAvg.SalesmanNo = @SalesmanNo
WHERE        (OSFA_DB.dbo.OT_ItemsQtyAvg.CompNo IS NULL) AND (ItemsPriority.CompanyID = @CompNo) AND (ISNULL(ItemsPriority.UseInSuggestedOrder, 0) = 1) AND (Customers.ID IN
                             (SELECT        CustomerNo
                                FROM            OSFA_DB.dbo.OT_CustomerMF
                                WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo))) AND (SalesPersonItemsAssignment.PositionsID = @PositionsID)
End


IF @ClientActive = 30 OR  @ClientActive = 0
BEGIN
--set @SendDate  = '2017-1-1'
	IF [dbo].[Fun_GetSalesmanSysOpValue](@CompNo,@SalesmanNo,425)=3
	BEGIN
		
		INSERT INTO OSFA_DB.dbo.OT_ItemsQtyAvg
								 (CompNo, SalesmanNo, CustomerNo, ItemNo, Avg_OrderQty, Avg_SalesQty, Avg_SalesRetQty)

		SELECT        ItemsSuggestGroupLink.CompanyID, @SalesmanNo AS SalesmanNo, ItemsSuggestGroupLink.CustomerID, ItemsSuggestGroupLink.SuggestGroupID, ItemsSuggestGroupLink.TargetCount, 
								 ISNULL(Fun_GetCustomerSuggestItemsTrCount_1.TrCount,0), 0 AS Expr2
		FROM            ItemsSuggestGroupLink INNER JOIN
								 OSFA_DB.dbo.OT_CustomerMF ON ItemsSuggestGroupLink.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND ItemsSuggestGroupLink.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
								 dbo.Fun_GetCustomerSuggestItemsTrCount(@CompNo,MONTH(@SendDate),YEAR(@SendDate)) AS Fun_GetCustomerSuggestItemsTrCount_1 ON ItemsSuggestGroupLink.CompanyID = Fun_GetCustomerSuggestItemsTrCount_1.CompanyID AND 
								 ItemsSuggestGroupLink.CustomerID = Fun_GetCustomerSuggestItemsTrCount_1.CustomerID AND ItemsSuggestGroupLink.SuggestGroupID = Fun_GetCustomerSuggestItemsTrCount_1.SuggestGroupID
		WHERE        (ItemsSuggestGroupLink.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (ItemsSuggestGroupLink.TargetMonth = MONTH(@SendDate)) AND (ItemsSuggestGroupLink.TargetYear = YEAR(@SendDate))
		
	END
	ELSE
	BEGIN

		INSERT INTO OSFA_DB.dbo.OT_ItemsQtyAvg
								 (CompNo, SalesmanNo, CustomerNo, ItemNo, Avg_OrderQty, Avg_SalesQty, Avg_SalesRetQty)

		SELECT        Fun_GetCustomerTarget_1.CompanyID, @SalesmanNo AS SalesmanNo, Fun_GetCustomerTarget_1.CustomerID, Fun_GetCustomerTarget_1.TargetReferenceID, Fun_GetCustomerTarget_1.TargetAmount, 
								 Fun_GetCustomerTarget_1.TrAmount, 0 AS Expr2
		FROM					 OSFA_DB.dbo.OT_CustomerMF As Custs   INNER JOIN
								 dbo.[Fun_GetCustomerTarget](@CompNo,MONTH(@SendDate),YEAR(@SendDate)) AS Fun_GetCustomerTarget_1 ON Custs.CompNo = Fun_GetCustomerTarget_1.CompanyID AND 
								 Custs.CustomerNo = Fun_GetCustomerTarget_1.CustomerID  
		WHERE        (Fun_GetCustomerTarget_1.CompanyID = @CompNo) AND (Custs.SalesmanNo = @SalesmanNo)  
	END


	--SELECT        ItemsSuggestGroupLink.CompanyID, @SalesmanNo AS SalesmanNo, ItemsSuggestGroupLink.CustomerID, ItemsSuggestGroupLink.SuggestGroupID, ItemsSuggestGroupLink.TargetCount,
	--						 Fun_GetCustomerSuggestItemsTrCount_1.TrCount, 0 AS Expr2
	--FROM            ItemsSuggestGroupLink INNER JOIN
	--						 OSFA_DB.dbo.OT_CustomerMF ON ItemsSuggestGroupLink.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND ItemsSuggestGroupLink.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
	--						 dbo.Fun_GetCustomerSuggestItemsTrCount(@CompNo) AS Fun_GetCustomerSuggestItemsTrCount_1 ON ItemsSuggestGroupLink.CompanyID = Fun_GetCustomerSuggestItemsTrCount_1.CompanyID AND 
	--						 ItemsSuggestGroupLink.CustomerID = Fun_GetCustomerSuggestItemsTrCount_1.CustomerID AND ItemsSuggestGroupLink.SuggestGroupID = Fun_GetCustomerSuggestItemsTrCount_1.SuggestGroupID
	--WHERE        (ItemsSuggestGroupLink.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

	set @SendDate  = GETDATE()

END


SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_ItemsQtyAvg [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')



---- -- - Order Delivery --------
IF @SalesmanCarID<>0 AND @ClientActive <> 27
BEGIN



if @ClientActive=173 -- Fadel Saleem



Begin

	SET @BeginTime = Convert(varchar(20),GetDate(),108)



	DELETE FROM OSFA_DB.dbo.OT_OrderHistoryDF

	FROM            OSFA_DB.dbo.OT_OrderHistoryDF INNER JOIN

							 OSFA_DB.dbo.OT_OrderHistoryHF ON OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND 

							 OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 

							 OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo INNER JOIN

							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 

							 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo

	WHERE        (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND OSFA_DB.dbo.OT_OrderHistoryHF.OrderState=99



	DELETE FROM OSFA_DB.dbo.OT_OrderHistoryHF

	FROM            OSFA_DB.dbo.OT_OrderHistoryHF INNER JOIN

							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 

							 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo

	WHERE        (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND OSFA_DB.dbo.OT_OrderHistoryHF.OrderState=99

	   

	INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryHF]

			   ([CompNo]

			   ,[OrderYear]

			   ,[OrderNo]

			   ,[OrderDate]

			   ,[SalesmanNo]

			   ,[CustomerNo]

			   ,[OrderState]

			   ,[Reason]

			   ,[OrderStateDesc]

			   ,[ReasonDesc]

			   ,[PO_No]

			   ,DiscountAmount

			   ,DiscountPercent

			   ,CustomerDiscountPerc

				,CustomerDiscountAmount

				,DeliveryOrderYear

				,DeliveryOrderNo	)

				SELECT DISTINCT 

										 SalesOrderDeliveryHF.[CompNo], SalesOrderDeliveryHF.OrderYear, SalesOrderDeliveryHF.OrderNo, SalesOrderDeliveryHF.OrderDate, SalesOrderDeliveryHF.[SalesmanNo], SalesOrderDeliveryHF.[CustomerNo], 

										 99 AS OrderState, SalesOrderDeliveryHF.Reason AS Reason, '' AS OrderStateDesc, '' AS ReasonDesc,  '' AS PO_No,SalesOrderDeliveryHF.DiscountAmount,SalesOrderDeliveryHF.DiscountPercent,SalesOrderDeliveryHF.CustomerDiscountPerc,SalesOrderDeliveryHF.CustomerDiscountAmount,SalesOrderDeliveryHF.OrderYear,SalesOrderDeliveryHF.[OrderNo]

				FROM            SalesOrderDeliveryHF INNER JOIN

										 OSFA_DB.dbo.OT_CustomerMF ON SalesOrderDeliveryHF.[CompNo] = OSFA_DB.dbo.OT_CustomerMF.CompNo AND SalesOrderDeliveryHF.[CustomerNo] = OSFA_DB.dbo.OT_CustomerMF.CustomerNo  LEFT OUTER JOIN

										 OSFA_DB.dbo.OT_OrderHistoryHF ON SalesOrderDeliveryHF.[CompNo] = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND SalesOrderDeliveryHF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 

										 SalesOrderDeliveryHF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo

				WHERE        (SalesOrderDeliveryHF.[CompNo] = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo IS NULL) 

				AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 

				--AND (SalesOrderDeliveryHF.CarID = @SalesmanCarID) AND (ISNULL(SalesOrderDeliveryHF.[IsDelivered],0)=0)



	SET @EndTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)

	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'SalesOrderDeliveryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')



	SET @BeginTime = Convert(varchar(20),GetDate(),108)



	INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryDF]

			   ([CompNo]

			   ,[OrderYear]

			   ,[OrderNo]

			   ,[ItemNo]

			   ,[UnitCode]

			   ,[OrderdQty]

			   ,[Bonus]

			   ,[DeliveredQty]

			   ,[OutstandingQty]

			   ,[SellValue]

			   ,[DiscPerc]

			   ,[DiscValue]

			   ,[TaxPerc]

			   ,[TaxValue]

			   ,[QtyOH]

			   ,[ItemDesc]

			   ,[InvQty]

			   ,VoucherDiscount

			   ,TaxType

			   ,UPrice

			   ,[Manual_Bonus])







	SELECT DISTINCT 

							 SalesOrderDeliveryDF.CompNo, SalesOrderDeliveryDF.OrderYear, SalesOrderDeliveryDF.OrderNo, SalesOrderDeliveryDF.[ItemNo], SalesOrderDeliveryDF.[UnitCode], SalesOrderDeliveryDF.OrderdQty, SalesOrderDeliveryDF.Bonus, 0 AS DeliveredQty, 0 AS OutstandingQty, 

							 SalesOrderDeliveryDF.SellValue, SalesOrderDeliveryDF.DiscPerc, SalesOrderDeliveryDF.DiscValue, SalesOrderDeliveryDF.TaxPerc, SalesOrderDeliveryDF.TaxValue, 0 AS QtyOH, Items.Name AS ItemDesc, 0 AS InvQty, SalesOrderDeliveryDF.VoucherDiscount, 

							 SalesOrderDeliveryDF.TaxType, SalesOrderDeliveryDF.UPrice, SalesOrderDeliveryDF.Manual_Bonus

	FROM            SalesOrderDeliveryHF INNER JOIN

							 SalesOrderDeliveryDF ON SalesOrderDeliveryHF.[CompNo] = SalesOrderDeliveryDF.[CompNo] AND SalesOrderDeliveryHF.OrderYear = SalesOrderDeliveryDF.OrderYear AND SalesOrderDeliveryHF.OrderNo = SalesOrderDeliveryDF.OrderNo INNER JOIN

							 OSFA_DB.dbo.OT_CustomerMF ON SalesOrderDeliveryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND SalesOrderDeliveryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo  INNER JOIN

							 Items ON SalesOrderDeliveryDF.[CompNo] = Items.CompanyID AND SalesOrderDeliveryDF.[ItemNo] = Items.ItemCode LEFT OUTER JOIN

							 OSFA_DB.dbo.OT_OrderHistoryDF ON SalesOrderDeliveryDF.[UnitCode] = OSFA_DB.dbo.OT_OrderHistoryDF.UnitCode AND SalesOrderDeliveryDF.CompNo = OSFA_DB.dbo.OT_OrderHistoryDF.CompNo AND 

							 SalesOrderDeliveryDF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear AND SalesOrderDeliveryDF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo AND 

							 SalesOrderDeliveryDF.[ItemNo] = OSFA_DB.dbo.OT_OrderHistoryDF.ItemNo

	WHERE        (SalesOrderDeliveryHF.[CompNo] = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo IS NULL) 

	AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) --AND (SalesOrderDeliveryHF.CarID = @SalesmanCarID)







	SET @EndTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)

	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'SalesOrderDeliveryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

	   	 



End



Else

Begin
	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	DELETE FROM OSFA_DB.dbo.OT_OrderHistoryDF
	FROM            OSFA_DB.dbo.OT_OrderHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_OrderHistoryHF ON OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
							 OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND OSFA_DB.dbo.OT_OrderHistoryHF.OrderState=99

	DELETE FROM OSFA_DB.dbo.OT_OrderHistoryHF
	FROM            OSFA_DB.dbo.OT_OrderHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND OSFA_DB.dbo.OT_OrderHistoryHF.OrderState=99
	   
	INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryHF]
			   ([CompNo]
			   ,[OrderYear]
			   ,[OrderNo]
			   ,[OrderDate]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[OrderState]
			   ,[Reason]
			   ,[OrderStateDesc]
			   ,[ReasonDesc]
			   ,[PO_No]
			   ,DiscountAmount
			   ,DiscountPercent
			   ,CustomerDiscountPerc
				,CustomerDiscountAmount
				,DeliveryOrderYear
				,DeliveryOrderNo	)
				SELECT DISTINCT 
										 SalesOrderDeliveryHF.[CompNo], SalesOrderDeliveryHF.OrderYear, SalesOrderDeliveryHF.OrderNo, SalesOrderDeliveryHF.OrderDate, SalesOrderDeliveryHF.[SalesmanNo], SalesOrderDeliveryHF.[CustomerNo], 
										 99 AS OrderState, '' AS Reason, '' AS OrderStateDesc, '' AS ReasonDesc, SalesOrderDeliveryHF.PO_NO AS PO_No,SalesOrderDeliveryHF.DiscountAmount,SalesOrderDeliveryHF.DiscountPercent,SalesOrderDeliveryHF.CustomerDiscountPerc,SalesOrderDeliveryHF.CustomerDiscountAmount,SalesOrderDeliveryHF.OrderYear,SalesOrderDeliveryHF.[OrderNo]
				FROM            SalesOrderDeliveryHF INNER JOIN
										 OSFA_DB.dbo.OT_CustomerMF ON SalesOrderDeliveryHF.[CompNo] = OSFA_DB.dbo.OT_CustomerMF.CompNo AND SalesOrderDeliveryHF.[CustomerNo] = OSFA_DB.dbo.OT_CustomerMF.CustomerNo  LEFT OUTER JOIN
										 OSFA_DB.dbo.OT_OrderHistoryHF ON SalesOrderDeliveryHF.[CompNo] = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND SalesOrderDeliveryHF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
										 SalesOrderDeliveryHF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo
				WHERE        (SalesOrderDeliveryHF.[CompNo] = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (SalesOrderDeliveryHF.CarID = @SalesmanCarID) AND (ISNULL(SalesOrderDeliveryHF.[IsDelivered],0)=0)

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'SalesOrderDeliveryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryDF]
			   ([CompNo]
			   ,[OrderYear]
			   ,[OrderNo]
			   ,[ItemNo]
			   ,[UnitCode]
			   ,[OrderdQty]
			   ,[Bonus]
			   ,[DeliveredQty]
			   ,[OutstandingQty]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[QtyOH]
			   ,[ItemDesc]
			   ,[InvQty]
			   ,VoucherDiscount
			   ,TaxType
			   ,UPrice
			   ,[Manual_Bonus])



	SELECT DISTINCT 
							 SalesOrderDeliveryDF.CompNo, SalesOrderDeliveryDF.OrderYear, SalesOrderDeliveryDF.OrderNo, SalesOrderDeliveryDF.[ItemNo], SalesOrderDeliveryDF.[UnitCode], SalesOrderDeliveryDF.OrderdQty, SalesOrderDeliveryDF.Bonus, 0 AS DeliveredQty, 0 AS OutstandingQty, 
							 SalesOrderDeliveryDF.SellValue, SalesOrderDeliveryDF.DiscPerc, SalesOrderDeliveryDF.DiscValue, SalesOrderDeliveryDF.TaxPerc, SalesOrderDeliveryDF.TaxValue, 0 AS QtyOH, Items.Name AS ItemDesc, 0 AS InvQty, SalesOrderDeliveryDF.VoucherDiscount, 
							 SalesOrderDeliveryDF.TaxType, SalesOrderDeliveryDF.UPrice, SalesOrderDeliveryDF.Manual_Bonus
	FROM            SalesOrderDeliveryHF INNER JOIN
							 SalesOrderDeliveryDF ON SalesOrderDeliveryHF.[CompNo] = SalesOrderDeliveryDF.[CompNo] AND SalesOrderDeliveryHF.OrderYear = SalesOrderDeliveryDF.OrderYear AND SalesOrderDeliveryHF.OrderNo = SalesOrderDeliveryDF.OrderNo INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON SalesOrderDeliveryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND SalesOrderDeliveryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo  INNER JOIN
							 Items ON SalesOrderDeliveryDF.[CompNo] = Items.CompanyID AND SalesOrderDeliveryDF.[ItemNo] = Items.ItemCode LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_OrderHistoryDF ON SalesOrderDeliveryDF.[UnitCode] = OSFA_DB.dbo.OT_OrderHistoryDF.UnitCode AND SalesOrderDeliveryDF.CompNo = OSFA_DB.dbo.OT_OrderHistoryDF.CompNo AND 
							 SalesOrderDeliveryDF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear AND SalesOrderDeliveryDF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo AND 
							 SalesOrderDeliveryDF.[ItemNo] = OSFA_DB.dbo.OT_OrderHistoryDF.ItemNo
	WHERE        (SalesOrderDeliveryHF.[CompNo] = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (SalesOrderDeliveryHF.CarID = @SalesmanCarID)



	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'SalesOrderDeliveryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
	 end  	 
END


---------------------------------------------------------------------------------
-- - SalesOrderHistory --------

if @ClientActive = 91  /*Nairoukh*/
Begin

Declare @fromdate2 smalldatetime =dateadd(DD,-60,getdate())


	SET @BeginTime = Convert(varchar(20),GetDate(),108)


	DELETE FROM OSFA_DB.dbo.OT_OrderHistoryDF
		FROM            OSFA_DB.dbo.OT_OrderHistoryDF INNER JOIN
								 OSFA_DB.dbo.OT_OrderHistoryHF ON OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND 
								 OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
								 OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo INNER JOIN
								 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
								 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
		WHERE        (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)   AND OSFA_DB.dbo.OT_OrderHistoryHF.OrderState<>99

		DELETE FROM OSFA_DB.dbo.OT_OrderHistoryHF
		FROM            OSFA_DB.dbo.OT_OrderHistoryHF INNER JOIN
								 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
								 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
		WHERE        (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)  AND OSFA_DB.dbo.OT_OrderHistoryHF.OrderState<>99

		INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryHF]
				   ([CompNo]
				   ,[OrderYear]
				   ,[OrderNo]
				   ,[OrderDate]
				   ,[SalesmanNo]
				   ,[CustomerNo]
				   ,[OrderState]
				   ,[Reason]
				   ,[OrderStateDesc]
				   ,[ReasonDesc]
				   ,[PO_No],[DiscountPercent])
		SELECT    distinct    SalesOrderHistoryHF.CompNo, SalesOrderHistoryHF.OrderYear, SalesOrderHistoryHF.OrderNo, SalesOrderHistoryHF.OrderDate, SalesOrderHistoryHF.SalesmanNo,
								  SalesOrderHistoryHF.CustomerNo, SalesOrderHistoryHF.OrderState, SalesOrderHistoryHF.Reason, SalesOrderHistoryHF.OrderStateDesc, 
								 SalesOrderHistoryHF.ReasonDesc, IsNull(SalesOrderHistoryHF.PO_No,'') AS PO_No,SalesOrderHistoryHF.[DiscountPercent]
		FROM            SalesOrderHistoryHF INNER JOIN
								 OSFA_DB.dbo.OT_CustomerMF ON SalesOrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
								 SalesOrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
								 OSFA_DB.dbo.OT_OrderHistoryHF ON SalesOrderHistoryHF.CompNo = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND 
								 SalesOrderHistoryHF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
								 SalesOrderHistoryHF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo
						   
		WHERE        (SalesOrderHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo IS NULL) AND 
								 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 
								 and SalesOrderHistoryHF.OrderYear=YEAR(getdate()) and @SalesmanNo not in(902,903,904,905,910,21,22)
								 and  SalesOrderHistoryHF.OrderDate between @fromdate2 and GETDATE()  
 
		SET @EndTime = Convert(varchar(20),GetDate(),108)
		INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
		VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_OrderHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

		SET @BeginTime = Convert(varchar(20),GetDate(),108)

		INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryDF]
				   ([CompNo]
				   ,[OrderYear]
				   ,[OrderNo]
				   ,[ItemNo]
				   ,[UnitCode]
				   ,[OrderdQty]
				   ,[Bonus]
				   ,[DeliveredQty]
				   ,[OutstandingQty]
				   ,[SellValue]
				   ,[DiscPerc]
				   ,[DiscValue]
				   ,[TaxPerc]
				   ,[TaxValue]
				   ,[QtyOH]
				   ,[ItemDesc]
				   ,[InvQty])
		SELECT    distinct    SalesOrderHistoryDF.CompNo, SalesOrderHistoryDF.OrderYear, SalesOrderHistoryDF.OrderNo, SalesOrderHistoryDF.ItemNo, SalesOrderHistoryDF.UnitCode, 
								 SalesOrderHistoryDF.OrderdQty, SalesOrderHistoryDF.Bonus, SalesOrderHistoryDF.DeliveredQty, SalesOrderHistoryDF.OutstandingQty, 
								 SalesOrderHistoryDF.SellValue-SalesOrderHistoryDF.TaxValue as SellValue, SalesOrderHistoryDF.DiscPerc, SalesOrderHistoryDF.DiscValue, SalesOrderHistoryDF.TaxPerc, SalesOrderHistoryDF.TaxValue, 
								 SalesOrderHistoryDF.QtyOH, SalesOrderHistoryDF.ItemDesc, IsNull(SalesOrderHistoryDF.InvQty,0) AS InvQty
		FROM            SalesOrderHistoryHF INNER JOIN
								 SalesOrderHistoryDF ON SalesOrderHistoryHF.CompNo = SalesOrderHistoryDF.CompNo AND SalesOrderHistoryHF.OrderYear = SalesOrderHistoryDF.OrderYear AND
								  SalesOrderHistoryHF.OrderNo = SalesOrderHistoryDF.OrderNo INNER JOIN
								 OSFA_DB.dbo.OT_CustomerMF ON SalesOrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
								 SalesOrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
								 OSFA_DB.dbo.OT_OrderHistoryDF ON SalesOrderHistoryDF.UnitCode = OSFA_DB.dbo.OT_OrderHistoryDF.UnitCode AND 
								 SalesOrderHistoryDF.CompNo = OSFA_DB.dbo.OT_OrderHistoryDF.CompNo AND 
								 SalesOrderHistoryDF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear AND SalesOrderHistoryDF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo AND
								  SalesOrderHistoryDF.ItemNo = OSFA_DB.dbo.OT_OrderHistoryDF.ItemNo
		WHERE        (SalesOrderHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo IS NULL) AND 
								 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)  and SalesOrderHistoryHF.OrderYear=YEAR(getdate())
								 and @SalesmanNo not in(902,903,904,905,910,21,22)
								  and  SalesOrderHistoryHF.OrderDate between @fromdate2 and GETDATE() 
	END


IF @ClientActive = 117-- /*Sukhtian*/ or @ClientActive = 117
BEGIN
Select 'Abna suktianorderhistory'

DECLARE @AccStatDays3 int=-60
DECLARE @AccStatFromDate3 date
SET @AccStatFromDate3=DATEADD(DAY,@AccStatDays3,@SendDate)

SET @BeginTime = Convert(varchar(20),GetDate(),108)

	DELETE FROM OSFA_DB.dbo.OT_OrderHistoryDF
	FROM            OSFA_DB.dbo.OT_OrderHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_OrderHistoryHF ON OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
							 OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 

	DELETE FROM OSFA_DB.dbo.OT_OrderHistoryHF
	FROM            OSFA_DB.dbo.OT_OrderHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
		
	INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryHF]
			   ([CompNo]
			   ,[OrderYear]
			   ,[OrderNo]
			   ,[OrderDate]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[OrderState]
			   ,[Reason]
			   ,[OrderStateDesc]
			   ,[ReasonDesc]
			   ,[PO_No]
			   ,DiscountAmount
			   ,DiscountPercent
			   ,CustomerDiscountPerc
				,CustomerDiscountAmount
			)
	SELECT DISTINCT 
							 OrdersHeaders.CompanyID, OrdersHeaders.OrderYear, OrdersHeaders.OrderNo, OrdersHeaders.OrderDate, OrdersHeaders.SalesPersonID, OrdersHeaders.CustomerID, 0 AS OrderState, ''AS Reason, 
							 '' AS OrderStateDesc, 'POSTED TO OLIVES'  AS ReasonDesc, '' AS PO_No, OrdersHeaders.DiscountAmount, OrdersHeaders.DiscountPercent, OrdersHeaders.CustomerDiscountPerc, OrdersHeaders.CustomerDiscountAmount
	FROM            OrdersHeaders INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND OrdersHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_OrderHistoryHF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND OrdersHeaders.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
							 OrdersHeaders.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo
	WHERE        (OrdersHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (OrdersHeaders.OrderDate > @AccStatFromDate3)
	Order By OrdersHeaders.OrderDate 

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_OrderHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryDF]
			   ([CompNo]
			   ,[OrderYear]
			   ,[OrderNo]
			   ,[ItemNo]
			   ,[UnitCode]
			   ,[OrderdQty]
			   ,[Bonus]
			   ,[DeliveredQty]
			   ,[OutstandingQty]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[QtyOH]
			   ,[ItemDesc]
			   ,[InvQty]
			   ,VoucherDiscount
			   ,TaxType
			   ,UPrice
			   ,[Manual_Bonus])

	SELECT DISTINCT 
							 OrdersDetails.CompanyID, OrdersDetails.OrderYear, OrdersDetails.OrderNo, OrdersDetails.ItemCode, OrdersDetails.UnitID, OrdersDetails.Quantity, OrdersDetails.Bonus, 0 AS DeliveredQty, 0 AS OutstandingQty, 
							 OrdersDetails.Price, OrdersDetails.DiscountPercent, OrdersDetails.DiscountAmount, OrdersDetails.TaxPercent, OrdersDetails.TaxAmount, 0 AS QtyOH, Items.Name AS ItemDesc, 0 AS InvQty, 
							 OrdersDetails.VoucherDiscount, OrdersDetails.TaxType, OrdersDetails.UPrice, OrdersDetails.Manual_Bonus
	FROM            OrdersHeaders INNER JOIN
							 OrdersDetails ON OrdersHeaders.CompanyID = OrdersDetails.CompanyID AND OrdersHeaders.OrderYear = OrdersDetails.OrderYear AND OrdersHeaders.OrderNo = OrdersDetails.OrderNo INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND OrdersHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
							 Items ON OrdersDetails.CompanyID = Items.CompanyID AND OrdersDetails.ItemCode = Items.ItemCode LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_OrderHistoryDF ON OrdersDetails.UnitID = OSFA_DB.dbo.OT_OrderHistoryDF.UnitCode AND OrdersDetails.CompanyID = OSFA_DB.dbo.OT_OrderHistoryDF.CompNo AND 
							 OrdersDetails.OrderYear = OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear AND OrdersDetails.OrderNo = OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo AND 
							 OrdersDetails.ItemCode = OSFA_DB.dbo.OT_OrderHistoryDF.ItemNo
	WHERE        (OrdersHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 
	

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_OrderHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
	   	 
END

if @ClientActive = 13 or @ClientActive = 153
BEGIN
DELETE FROM OSFA_DB.dbo.OT_OrderHistoryDF
	FROM            OSFA_DB.dbo.OT_OrderHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_OrderHistoryHF ON OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
							 OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 

	DELETE FROM OSFA_DB.dbo.OT_OrderHistoryHF
	FROM            OSFA_DB.dbo.OT_OrderHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)


	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryHF]
			   ([CompNo]
			   ,[OrderYear]
			   ,[OrderNo]
			   ,[OrderDate]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[OrderState]
			   ,[Reason]
			   ,[OrderStateDesc]
			   ,[ReasonDesc]
			   ,[PO_No]
			   ,DiscountAmount
			   ,DiscountPercent
			   ,CustomerDiscountPerc
				,CustomerDiscountAmount
			)
SELECT DISTINCT 
                         OrdersHeaders.CompanyID, OrdersHeaders.OrderYear, OrdersHeaders.OrderNo, OrdersHeaders.OrderDate, OrdersHeaders.SalesPersonID, OrdersHeaders.CustomerID, 0 AS OrderState, ''AS Reason, 
                         '' AS OrderStateDesc, 'POSTED TO OLIVES'  AS ReasonDesc, '' AS PO_No, OrdersHeaders.DiscountAmount, OrdersHeaders.DiscountPercent, OrdersHeaders.CustomerDiscountPerc, OrdersHeaders.CustomerDiscountAmount
FROM            OrdersHeaders INNER JOIN
                         OSFA_DB.dbo.OT_CustomerMF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND OrdersHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
                         OSFA_DB.dbo.OT_OrderHistoryHF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND OrdersHeaders.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
                         OrdersHeaders.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo
WHERE        (OrdersHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)and OSFA_DB.dbo.OT_CustomerMF.SalesmanNo <>110

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_OrderHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

	SET @BeginTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryDF]
			   ([CompNo]
			   ,[OrderYear]
			   ,[OrderNo]
			   ,[ItemNo]
			   ,[UnitCode]
			   ,[OrderdQty]
			   ,[Bonus]
			   ,[DeliveredQty]
			   ,[OutstandingQty]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[QtyOH]
			   ,[ItemDesc]
			   ,[InvQty]
			   ,VoucherDiscount
			   ,TaxType
			   ,UPrice
			   ,[Manual_Bonus])

SELECT DISTINCT 
                         OrdersDetails.CompanyID, OrdersDetails.OrderYear, OrdersDetails.OrderNo, OrdersDetails.ItemCode, OrdersDetails.UnitID, OrdersDetails.Quantity, OrdersDetails.Bonus, 0 AS DeliveredQty, 0 AS OutstandingQty, 
                         OrdersDetails.Price, OrdersDetails.DiscountPercent, OrdersDetails.DiscountAmount, OrdersDetails.TaxPercent, OrdersDetails.TaxAmount, 0 AS QtyOH, Items.Name AS ItemDesc, 0 AS InvQty, 
                         OrdersDetails.VoucherDiscount, OrdersDetails.TaxType, OrdersDetails.UPrice, OrdersDetails.Manual_Bonus
FROM            OrdersHeaders INNER JOIN
                         OrdersDetails ON OrdersHeaders.CompanyID = OrdersDetails.CompanyID AND OrdersHeaders.OrderYear = OrdersDetails.OrderYear AND OrdersHeaders.OrderNo = OrdersDetails.OrderNo INNER JOIN
                         OSFA_DB.dbo.OT_CustomerMF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND OrdersHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
                         Items ON OrdersDetails.CompanyID = Items.CompanyID AND OrdersDetails.ItemCode = Items.ItemCode LEFT OUTER JOIN
                         OSFA_DB.dbo.OT_OrderHistoryDF ON OrdersDetails.UnitID = OSFA_DB.dbo.OT_OrderHistoryDF.UnitCode AND OrdersDetails.CompanyID = OSFA_DB.dbo.OT_OrderHistoryDF.CompNo AND 
                         OrdersDetails.OrderYear = OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear AND OrdersDetails.OrderNo = OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo AND 
                         OrdersDetails.ItemCode = OSFA_DB.dbo.OT_OrderHistoryDF.ItemNo
WHERE        (OrdersHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)and OSFA_DB.dbo.OT_CustomerMF.SalesmanNo <>110



	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_OrderHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')




END


	-----------------


IF @ClientActive =92 --- ÇáãäÌÏ
BEGIN
DELETE FROM OSFA_DB.dbo.OT_OrderHistoryDF
	FROM            OSFA_DB.dbo.OT_OrderHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_OrderHistoryHF ON OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
							 OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 

	DELETE FROM OSFA_DB.dbo.OT_OrderHistoryHF
	FROM            OSFA_DB.dbo.OT_OrderHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)


	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryHF]
			   ([CompNo]
			   ,[OrderYear]
			   ,[OrderNo]
			   ,[OrderDate]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[OrderState]
			   ,[Reason]
			   ,[OrderStateDesc]
			   ,[ReasonDesc]
			   ,[PO_No]
			   ,DiscountAmount
			   ,DiscountPercent
			   ,CustomerDiscountPerc
				,CustomerDiscountAmount
			)
SELECT DISTINCT 
                         OrdersHeaders.CompanyID, OrdersHeaders.OrderYear, OrdersHeaders.OrderNo, OrdersHeaders.OrderDate, OrdersHeaders.SalesPersonID, OrdersHeaders.CustomerID, 0 AS OrderState, ''AS Reason, 
                         '' AS OrderStateDesc, 'POSTED TO OLIVES'  AS ReasonDesc, '' AS PO_No, OrdersHeaders.DiscountAmount, OrdersHeaders.DiscountPercent, OrdersHeaders.CustomerDiscountPerc, OrdersHeaders.CustomerDiscountAmount
FROM            OrdersHeaders INNER JOIN
                         OSFA_DB.dbo.OT_CustomerMF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND OrdersHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
                         OSFA_DB.dbo.OT_OrderHistoryHF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND OrdersHeaders.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
                         OrdersHeaders.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo
WHERE        (OrdersHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_OrderHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryDF]
			   ([CompNo]
			   ,[OrderYear]
			   ,[OrderNo]
			   ,[ItemNo]
			   ,[UnitCode]
			   ,[OrderdQty]
			   ,[Bonus]
			   ,[DeliveredQty]
			   ,[OutstandingQty]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[QtyOH]
			   ,[ItemDesc]
			   ,[InvQty]
			   ,VoucherDiscount
			   ,TaxType
			   ,UPrice
			   ,[Manual_Bonus])

SELECT DISTINCT 
                         OrdersDetails.CompanyID, OrdersDetails.OrderYear, OrdersDetails.OrderNo, OrdersDetails.ItemCode, OrdersDetails.UnitID, OrdersDetails.Quantity, OrdersDetails.Bonus, 0 AS DeliveredQty, 0 AS OutstandingQty, 
                         OrdersDetails.Price, OrdersDetails.DiscountPercent, OrdersDetails.DiscountAmount, OrdersDetails.TaxPercent, OrdersDetails.TaxAmount, 0 AS QtyOH, Items.Name AS ItemDesc, 0 AS InvQty, 
                         OrdersDetails.VoucherDiscount, OrdersDetails.TaxType, OrdersDetails.UPrice, OrdersDetails.Manual_Bonus
FROM            OrdersHeaders INNER JOIN
                         OrdersDetails ON OrdersHeaders.CompanyID = OrdersDetails.CompanyID AND OrdersHeaders.OrderYear = OrdersDetails.OrderYear AND OrdersHeaders.OrderNo = OrdersDetails.OrderNo INNER JOIN
                         OSFA_DB.dbo.OT_CustomerMF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND OrdersHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
                         Items ON OrdersDetails.CompanyID = Items.CompanyID AND OrdersDetails.ItemCode = Items.ItemCode LEFT OUTER JOIN
                         OSFA_DB.dbo.OT_OrderHistoryDF ON OrdersDetails.UnitID = OSFA_DB.dbo.OT_OrderHistoryDF.UnitCode AND OrdersDetails.CompanyID = OSFA_DB.dbo.OT_OrderHistoryDF.CompNo AND 
                         OrdersDetails.OrderYear = OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear AND OrdersDetails.OrderNo = OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo AND 
                         OrdersDetails.ItemCode = OSFA_DB.dbo.OT_OrderHistoryDF.ItemNo
WHERE        (OrdersHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)



	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_OrderHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')


END


IF @ClientActive = 74  or @ClientActive = 111  or @ClientActive = 112  Or @ClientActive=29 or @ClientActive=176 or @ClientActive=32 /*Sukhtian*/ --/Hayat//
BEGIN
DECLARE @AccStatDays int=-60
DECLARE @AccStatFromDate date
SET @AccStatFromDate=DATEADD(DAY,@AccStatDays,@SendDate)

SET @BeginTime = Convert(varchar(20),GetDate(),108)

	DELETE FROM OSFA_DB.dbo.OT_OrderHistoryDF
	FROM            OSFA_DB.dbo.OT_OrderHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_OrderHistoryHF ON OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
							 OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 

	DELETE FROM OSFA_DB.dbo.OT_OrderHistoryHF
	FROM            OSFA_DB.dbo.OT_OrderHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
		
	INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryHF]
			   ([CompNo]
			   ,[OrderYear]
			   ,[OrderNo]
			   ,[OrderDate]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[OrderState]
			   ,[Reason]
			   ,[OrderStateDesc]
			   ,[ReasonDesc]
			   ,[PO_No]
			   ,DiscountAmount
			   ,DiscountPercent
			   ,CustomerDiscountPerc
				,CustomerDiscountAmount
			)
	SELECT DISTINCT 
							 OrdersHeaders.CompanyID, OrdersHeaders.OrderYear, OrdersHeaders.OrderNo, OrdersHeaders.OrderDate, OrdersHeaders.SalesPersonID, OrdersHeaders.CustomerID, 0 AS OrderState, ''AS Reason, 
							 '' AS OrderStateDesc, 'POSTED TO OLIVES'  AS ReasonDesc, '' AS PO_No, OrdersHeaders.DiscountAmount, OrdersHeaders.DiscountPercent, OrdersHeaders.CustomerDiscountPerc, OrdersHeaders.CustomerDiscountAmount
	FROM            OrdersHeaders INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND OrdersHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_OrderHistoryHF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND OrdersHeaders.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
							 OrdersHeaders.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo
	WHERE        (OrdersHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (OrdersHeaders.OrderDate > @AccStatFromDate)
	Order By OrdersHeaders.OrderDate 

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_OrderHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryDF]
			   ([CompNo]
			   ,[OrderYear]
			   ,[OrderNo]
			   ,[ItemNo]
			   ,[UnitCode]
			   ,[OrderdQty]
			   ,[Bonus]
			   ,[DeliveredQty]
			   ,[OutstandingQty]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[QtyOH]
			   ,[ItemDesc]
			   ,[InvQty]
			   ,VoucherDiscount
			   ,TaxType
			   ,UPrice
			   ,[Manual_Bonus])

	SELECT DISTINCT 
							 OrdersDetails.CompanyID, OrdersDetails.OrderYear, OrdersDetails.OrderNo, OrdersDetails.ItemCode, OrdersDetails.UnitID, OrdersDetails.Quantity, OrdersDetails.Bonus, 0 AS DeliveredQty, 0 AS OutstandingQty, 
							 OrdersDetails.Price, OrdersDetails.DiscountPercent, OrdersDetails.DiscountAmount, OrdersDetails.TaxPercent, OrdersDetails.TaxAmount, 0 AS QtyOH, Items.Name AS ItemDesc, 0 AS InvQty, 
							 OrdersDetails.VoucherDiscount, OrdersDetails.TaxType, OrdersDetails.UPrice, OrdersDetails.Manual_Bonus
	FROM            OrdersHeaders INNER JOIN
							 OrdersDetails ON OrdersHeaders.CompanyID = OrdersDetails.CompanyID AND OrdersHeaders.OrderYear = OrdersDetails.OrderYear AND OrdersHeaders.OrderNo = OrdersDetails.OrderNo INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND OrdersHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
							 Items ON OrdersDetails.CompanyID = Items.CompanyID AND OrdersDetails.ItemCode = Items.ItemCode LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_OrderHistoryDF ON OrdersDetails.UnitID = OSFA_DB.dbo.OT_OrderHistoryDF.UnitCode AND OrdersDetails.CompanyID = OSFA_DB.dbo.OT_OrderHistoryDF.CompNo AND 
							 OrdersDetails.OrderYear = OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear AND OrdersDetails.OrderNo = OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo AND 
							 OrdersDetails.ItemCode = OSFA_DB.dbo.OT_OrderHistoryDF.ItemNo
	WHERE        (OrdersHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 
	

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_OrderHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
	   	 
END



else IF @ClientActive = 95
BEGIN

set  @AccStatDays =-60
SET @AccStatFromDate=DATEADD(DAY,@AccStatDays,@SendDate)

SET @BeginTime = Convert(varchar(20),GetDate(),108)

select @AccStatFromDate
	DELETE FROM OSFA_DB.dbo.OT_OrderHistoryDF
	FROM            OSFA_DB.dbo.OT_OrderHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_OrderHistoryHF ON OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
							 OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 

	DELETE FROM OSFA_DB.dbo.OT_OrderHistoryHF
	FROM            OSFA_DB.dbo.OT_OrderHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
		
	INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryHF]
			   ([CompNo]
			   ,[OrderYear]
			   ,[OrderNo]
			   ,[OrderDate]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[OrderState]
			   ,[Reason]
			   ,[OrderStateDesc]
			   ,[ReasonDesc]
			   ,[PO_No]
			   ,DiscountAmount
			   ,DiscountPercent
			   ,CustomerDiscountPerc
				,CustomerDiscountAmount
			)
	SELECT DISTINCT 
							 OrdersHeaders.CompanyID, OrdersHeaders.OrderYear, OrdersHeaders.OrderNo, OrdersHeaders.OrderDate, OrdersHeaders.SalesPersonID, OrdersHeaders.CustomerID, 0 AS OrderState, ''AS Reason, 
							 '' AS OrderStateDesc, 'POSTED TO OLIVES'  AS ReasonDesc, '' AS PO_No, OrdersHeaders.DiscountAmount, OrdersHeaders.DiscountPercent, OrdersHeaders.CustomerDiscountPerc, OrdersHeaders.CustomerDiscountAmount
	FROM            OrdersHeaders INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND OrdersHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_OrderHistoryHF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND OrdersHeaders.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
							 OrdersHeaders.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo
	WHERE        (OrdersHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
	AND (OrdersHeaders.OrderDate > @AccStatFromDate)
	Order By OrdersHeaders.OrderDate 

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_OrderHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryDF]
			   ([CompNo]
			   ,[OrderYear]
			   ,[OrderNo]
			   ,[ItemNo]
			   ,[UnitCode]
			   ,[OrderdQty]
			   ,[Bonus]
			   ,[DeliveredQty]
			   ,[OutstandingQty]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[QtyOH]
			   ,[ItemDesc]
			   ,[InvQty]
			   ,VoucherDiscount
			   ,TaxType
			   ,UPrice
			   ,[Manual_Bonus])

	SELECT DISTINCT 
							 OrdersDetails.CompanyID, OrdersDetails.OrderYear, OrdersDetails.OrderNo, OrdersDetails.ItemCode, OrdersDetails.UnitID, OrdersDetails.Quantity, OrdersDetails.Bonus, 0 AS DeliveredQty, 0 AS OutstandingQty, 
							 OrdersDetails.Price, OrdersDetails.DiscountPercent, OrdersDetails.DiscountAmount, OrdersDetails.TaxPercent, OrdersDetails.TaxAmount, 0 AS QtyOH, Items.Name AS ItemDesc, 0 AS InvQty, 
							 OrdersDetails.VoucherDiscount, OrdersDetails.TaxType, (OrdersDetails.UPrice*OrdersDetails.TaxPercent/100)+OrdersDetails.UPrice, OrdersDetails.Manual_Bonus
	FROM            OrdersHeaders INNER JOIN
							 OrdersDetails ON OrdersHeaders.CompanyID = OrdersDetails.CompanyID AND OrdersHeaders.OrderYear = OrdersDetails.OrderYear AND OrdersHeaders.OrderNo = OrdersDetails.OrderNo INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND OrdersHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
							 Items ON OrdersDetails.CompanyID = Items.CompanyID AND OrdersDetails.ItemCode = Items.ItemCode LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_OrderHistoryDF ON OrdersDetails.UnitID = OSFA_DB.dbo.OT_OrderHistoryDF.UnitCode AND OrdersDetails.CompanyID = OSFA_DB.dbo.OT_OrderHistoryDF.CompNo AND 
							 OrdersDetails.OrderYear = OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear AND OrdersDetails.OrderNo = OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo AND 
							 OrdersDetails.ItemCode = OSFA_DB.dbo.OT_OrderHistoryDF.ItemNo
	WHERE        (OrdersHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 
	

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_OrderHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
	   	 
END


ELSE if @ClientActive = 61 /*Rema Plastic*/ or @ClientActive = 38
BEGIN
	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	DELETE FROM OSFA_DB.dbo.OT_OrderHistoryDF
	FROM            OSFA_DB.dbo.OT_OrderHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_OrderHistoryHF ON OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
							 OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 

	DELETE FROM OSFA_DB.dbo.OT_OrderHistoryHF
	FROM            OSFA_DB.dbo.OT_OrderHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
			

	INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryHF]
			   ([CompNo]
			   ,[OrderYear]
			   ,[OrderNo]
			   ,[OrderDate]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[OrderState]
			   ,[Reason]
			   ,[OrderStateDesc]
			   ,[ReasonDesc]
			   ,[PO_No]
			   ,DiscountAmount
			   ,DiscountPercent
			   ,CustomerDiscountPerc
				,CustomerDiscountAmount
			)
	SELECT DISTINCT 
							 OrdersHeaders.CompanyID, OrdersHeaders.OrderYear, OrdersHeaders.OrderNo, OrdersHeaders.OrderDate, OrdersHeaders.SalesPersonID, OrdersHeaders.CustomerID, 0 AS OrderState, '' AS Reason, 
							 Case when OrdersHeaders.WFApproved=0 then 'Rejected' else 'Approved' end  AS OrderStateDesc, Case when OrdersHeaders.WFApproved=0 then 'Rejected' else 'Approved' end AS ReasonDesc, '' AS PO_No, OrdersHeaders.DiscountAmount, OrdersHeaders.DiscountPercent, OrdersHeaders.CustomerDiscountPerc, OrdersHeaders.CustomerDiscountAmount
	FROM            OrdersHeaders INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND OrdersHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_OrderHistoryHF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND OrdersHeaders.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
							 OrdersHeaders.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo
	WHERE        (OrdersHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_OrderHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryDF]
			   ([CompNo]
			   ,[OrderYear]
			   ,[OrderNo]
			   ,[ItemNo]
			   ,[UnitCode]
			   ,[OrderdQty]
			   ,[Bonus]
			   ,[DeliveredQty]
			   ,[OutstandingQty]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[QtyOH]
			   ,[ItemDesc]
			   ,[InvQty]
			   ,VoucherDiscount
			   ,TaxType
			   ,UPrice
			   ,[Manual_Bonus])

	SELECT DISTINCT 
							 OrdersDetails.CompanyID, OrdersDetails.OrderYear, OrdersDetails.OrderNo, OrdersDetails.ItemCode, OrdersDetails.UnitID, OrdersDetails.Quantity, OrdersDetails.Bonus, 0 AS DeliveredQty, 0 AS OutstandingQty, 
							 OrdersDetails.Price, OrdersDetails.DiscountPercent, OrdersDetails.DiscountAmount, OrdersDetails.TaxPercent, OrdersDetails.TaxAmount, 0 AS QtyOH, Items.Name AS ItemDesc, 0 AS InvQty, 
							 OrdersDetails.VoucherDiscount, OrdersDetails.TaxType, OrdersDetails.UPrice, OrdersDetails.Manual_Bonus
	FROM            OrdersHeaders INNER JOIN
							 OrdersDetails ON OrdersHeaders.CompanyID = OrdersDetails.CompanyID AND OrdersHeaders.OrderYear = OrdersDetails.OrderYear AND OrdersHeaders.OrderNo = OrdersDetails.OrderNo INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OrdersHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND OrdersHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
							 Items ON OrdersDetails.CompanyID = Items.CompanyID AND OrdersDetails.ItemCode = Items.ItemCode LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_OrderHistoryDF ON OrdersDetails.UnitID = OSFA_DB.dbo.OT_OrderHistoryDF.UnitCode AND OrdersDetails.CompanyID = OSFA_DB.dbo.OT_OrderHistoryDF.CompNo AND 
							 OrdersDetails.OrderYear = OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear AND OrdersDetails.OrderNo = OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo AND 
							 OrdersDetails.ItemCode = OSFA_DB.dbo.OT_OrderHistoryDF.ItemNo
	WHERE        (OrdersHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)



	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_OrderHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
	END
	ELSE
BEGIN
	IF  @ClientActive not in( 27,91,153,117,13) /*(Qima Masieh,Nairoulh)Sukhtian*/
	BEGIN
		SET @BeginTime = Convert(varchar(20),GetDate(),108)

		DELETE FROM OSFA_DB.dbo.OT_OrderHistoryDF
		FROM            OSFA_DB.dbo.OT_OrderHistoryDF INNER JOIN
								 OSFA_DB.dbo.OT_OrderHistoryHF ON OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND 
								 OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
								 OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo INNER JOIN
								 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
								 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
		WHERE        (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)   AND OSFA_DB.dbo.OT_OrderHistoryHF.OrderState<>99

		DELETE FROM OSFA_DB.dbo.OT_OrderHistoryHF
		FROM            OSFA_DB.dbo.OT_OrderHistoryHF INNER JOIN
								 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
								 OSFA_DB.dbo.OT_OrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
		WHERE        (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)  AND OSFA_DB.dbo.OT_OrderHistoryHF.OrderState<>99

		INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryHF]
				   ([CompNo]
				   ,[OrderYear]
				   ,[OrderNo]
				   ,[OrderDate]
				   ,[SalesmanNo]
				   ,[CustomerNo]
				   ,[OrderState]
				   ,[Reason]
				   ,[OrderStateDesc]
				   ,[ReasonDesc]
				   ,[PO_No],[DiscountPercent])
		SELECT    distinct    SalesOrderHistoryHF.CompNo, SalesOrderHistoryHF.OrderYear, SalesOrderHistoryHF.OrderNo, SalesOrderHistoryHF.OrderDate, SalesOrderHistoryHF.SalesmanNo,
								  SalesOrderHistoryHF.CustomerNo, SalesOrderHistoryHF.OrderState, SalesOrderHistoryHF.Reason, SalesOrderHistoryHF.OrderStateDesc, 
								 SalesOrderHistoryHF.ReasonDesc, IsNull(SalesOrderHistoryHF.PO_No,'') AS PO_No,SalesOrderHistoryHF.[DiscountPercent]
		FROM            SalesOrderHistoryHF INNER JOIN
								 OSFA_DB.dbo.OT_CustomerMF ON SalesOrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
								 SalesOrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
								 OSFA_DB.dbo.OT_OrderHistoryHF ON SalesOrderHistoryHF.CompNo = OSFA_DB.dbo.OT_OrderHistoryHF.CompNo AND 
								 SalesOrderHistoryHF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryHF.OrderYear AND 
								 SalesOrderHistoryHF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryHF.OrderNo
		WHERE        (SalesOrderHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryHF.CompNo IS NULL) AND 
								 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

		SET @EndTime = Convert(varchar(20),GetDate(),108)
		INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
		VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_OrderHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

		SET @BeginTime = Convert(varchar(20),GetDate(),108)

		INSERT INTO [OSFA_DB].[dbo].[OT_OrderHistoryDF]
				   ([CompNo]
				   ,[OrderYear]
				   ,[OrderNo]
				   ,[ItemNo]
				   ,[UnitCode]
				   ,[OrderdQty]
				   ,[Bonus]
				   ,[DeliveredQty]
				   ,[OutstandingQty]
				   ,[SellValue]
				   ,[DiscPerc]
				   ,[DiscValue]
				   ,[TaxPerc]
				   ,[TaxValue]
				   ,[QtyOH]
				   ,[ItemDesc]
				   ,[InvQty])
		SELECT    distinct    SalesOrderHistoryDF.CompNo, SalesOrderHistoryDF.OrderYear, SalesOrderHistoryDF.OrderNo, SalesOrderHistoryDF.ItemNo, SalesOrderHistoryDF.UnitCode, 
								 SalesOrderHistoryDF.OrderdQty, SalesOrderHistoryDF.Bonus, SalesOrderHistoryDF.DeliveredQty, SalesOrderHistoryDF.OutstandingQty, 
								 SalesOrderHistoryDF.SellValue, SalesOrderHistoryDF.DiscPerc, SalesOrderHistoryDF.DiscValue, SalesOrderHistoryDF.TaxPerc, SalesOrderHistoryDF.TaxValue, 
								 SalesOrderHistoryDF.QtyOH, SalesOrderHistoryDF.ItemDesc, IsNull(SalesOrderHistoryDF.InvQty,0) AS InvQty
		FROM            SalesOrderHistoryHF INNER JOIN
								 SalesOrderHistoryDF ON SalesOrderHistoryHF.CompNo = SalesOrderHistoryDF.CompNo AND SalesOrderHistoryHF.OrderYear = SalesOrderHistoryDF.OrderYear AND
								  SalesOrderHistoryHF.OrderNo = SalesOrderHistoryDF.OrderNo INNER JOIN
								 OSFA_DB.dbo.OT_CustomerMF ON SalesOrderHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
								 SalesOrderHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
								 OSFA_DB.dbo.OT_OrderHistoryDF ON SalesOrderHistoryDF.UnitCode = OSFA_DB.dbo.OT_OrderHistoryDF.UnitCode AND 
								 SalesOrderHistoryDF.CompNo = OSFA_DB.dbo.OT_OrderHistoryDF.CompNo AND 
								 SalesOrderHistoryDF.OrderYear = OSFA_DB.dbo.OT_OrderHistoryDF.OrderYear AND SalesOrderHistoryDF.OrderNo = OSFA_DB.dbo.OT_OrderHistoryDF.OrderNo AND
								  SalesOrderHistoryDF.ItemNo = OSFA_DB.dbo.OT_OrderHistoryDF.ItemNo
		WHERE        (SalesOrderHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_OrderHistoryDF.CompNo IS NULL) AND 
								 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)


		SET @EndTime = Convert(varchar(20),GetDate(),108)
		INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
		VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_OrderHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
	END
END
 

SET @BeginTime = Convert(varchar(20),GetDate(),108)

DECLARE @UseInvoiceDelivery int = 0
SELECT @UseInvoiceDelivery = COUNT(*) 
FROM OSFA_DB.dbo.OT_SystemOptions 
WHERE CompNo = @CompNo AND Op_ID = 365 AND SalesmanNo in(0,@SalesmanNo) AND Op_Value = '1'

---- -- - Invoice Delivery --------
IF @UseInvoiceDelivery <> 0
Begin 

	
	if @ClientActive =68
	Begin
	select 'Oth1'
	
	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF left outer JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryDF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear AND OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType
	WHERE        (OSFA_DB.dbo.OT_CustomerMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) and (OSFA_DB.dbo.OT_InvoiceHistoryHF.SalesmanNo is null)
	

				DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF where CompNo=@CompNo and SalesmanNo=@SalesmanNo   

 

	

				
	  

	select '5555'
		INSERT INTO [OSFA_DB].[dbo].OT_InvoiceHistoryHF
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[VouDate]
			   ,[StoreNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]           
			   ,[VouDiscPerc]
				,[CustomerDiscPerc]
				,[Notes]
				,[IsForDelivery]
				,[SalesmanName]
				,[InvStatus],Ref1
				,Ref2)
SELECT DISTINCT 
                         xbt.CompNo, xbt.VouYear, xbt.VouNo, xbt.VouType, xbt.VouDate, xbt.Expr2, xbt.DeliveredSalesmanNo AS Expr1, xbt.CustomerNo, xbt.VouDiscPerc, xbt.CustomerDiscPerc, xbt.Notes, 
                         CASE WHEN OSFA_DB.dbo.OT_InvoicesDelivery.CompanyID IS NULL AND xbt.DeliveredSalesmanNo IS NOT NULL AND xbt.DeliveredSalesmanNo = @SalesmanNo THEN 1 ELSE 0 END AS IsForDelivery, xbt.Name, 
                         xbt.Name AS Expr3, xbt.PaymentTypeID, xbt.VouNo AS Expr4
FROM            (SELECT DISTINCT 
                                                    TOP (100) PERCENT InvoiceDeliveryHF.CompNo, InvoiceDeliveryHF.VouYear, InvoiceDeliveryHF.VouNo, InvoiceDeliveryHF.VouType, InvoiceDeliveryHF.VouDate, InvoiceDeliveryHF.SalesmanNo AS Expr2, 
                                                    InvoiceDeliveryHF.DeliveredSalesmanNo, InvoiceDeliveryHF.CustomerNo, InvoiceDeliveryHF.VouDiscPerc, InvoiceDeliveryHF.CustomerDiscPerc, InvoiceDeliveryHF.Notes, 1 AS Expr1, SalesPersons.Name, 
                                                    InvoiceDeliveryHF.PaymentTypeID
                           FROM            InvoiceDeliveryHF INNER JOIN
                                                    OSFA_DB.dbo.OT_CustomerMF ON InvoiceDeliveryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND InvoiceDeliveryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
                                                    SalesPersons ON InvoiceDeliveryHF.SalesmanNo = SalesPersons.ID AND InvoiceDeliveryHF.CompNo = SalesPersons.CompanyID LEFT OUTER JOIN
                                                    OSFA_DB.dbo.OT_InvoiceHistoryHF ON InvoiceDeliveryHF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND InvoiceDeliveryHF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND 
                                                    InvoiceDeliveryHF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND InvoiceDeliveryHF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType
                           WHERE        (InvoiceDeliveryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (InvoiceDeliveryHF.DeliveredSalesmanNo IS NOT NULL)
                           ORDER BY InvoiceDeliveryHF.VouDate) AS xbt LEFT OUTER JOIN
                         OSFA_DB.dbo.OT_InvoiceHistoryHF AS OT_InvoiceHistoryHF_1 ON xbt.CompNo = OT_InvoiceHistoryHF_1.CompNo AND xbt.VouYear = OT_InvoiceHistoryHF_1.VouYear AND xbt.VouNo = OT_InvoiceHistoryHF_1.VouNo AND 
                         xbt.VouType = OT_InvoiceHistoryHF_1.VouType LEFT OUTER JOIN
                         OSFA_DB.dbo.OT_InvoicesDelivery ON xbt.CompNo = OSFA_DB.dbo.OT_InvoicesDelivery.CompanyID AND xbt.VouNo = OSFA_DB.dbo.OT_InvoicesDelivery.TransactionNo AND 
                         xbt.VouType = OSFA_DB.dbo.OT_InvoicesDelivery.TransactionTypeID AND xbt.VouYear = OSFA_DB.dbo.OT_InvoicesDelivery.TransactionYear
WHERE        (OT_InvoiceHistoryHF_1.CompNo IS NULL)	 
								--where xbt.VouNo not in(378,508,2961,1713,1775, 2136,2237)

		INSERT INTO [OSFA_DB].[dbo].OT_InvoiceHistoryDF
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[ItemNo]
			   ,[BatchNo]
			   ,[UnitCode]
			   ,[Qty]
			   ,[Bonus]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[ItemDesc]
			   ,TaxType
			   ,[UnitPrice])
SELECT        InvoiceDeliveryDF.CompNo, InvoiceDeliveryDF.VouYear, InvoiceDeliveryDF.VouNo, InvoiceDeliveryDF.VouType, InvoiceDeliveryDF.ItemNo, InvoiceDeliveryDF.BatchNo, InvoiceDeliveryDF.UnitCode, InvoiceDeliveryDF.Qty, 
                         InvoiceDeliveryDF.Bonus, InvoiceDeliveryDF.SellValue, InvoiceDeliveryDF.DiscPerc, InvoiceDeliveryDF.DiscValue, InvoiceDeliveryDF.TaxPerc, InvoiceDeliveryDF.TaxValue, InvoiceDeliveryDF.ItemDesc, 
                         OSFA_DB.dbo.OT_InvoiceHistoryDF.TaxType, OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitPrice
FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF RIGHT OUTER JOIN
                         InvoiceDeliveryHF INNER JOIN
                         InvoiceDeliveryDF ON InvoiceDeliveryHF.CompNo = InvoiceDeliveryDF.CompNo AND InvoiceDeliveryHF.VouYear = InvoiceDeliveryDF.VouYear AND InvoiceDeliveryHF.VouNo = InvoiceDeliveryDF.VouNo AND 
                         InvoiceDeliveryHF.VouType = InvoiceDeliveryDF.VouType INNER JOIN
                         OSFA_DB.dbo.OT_CustomerMF ON InvoiceDeliveryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND InvoiceDeliveryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo ON 
                         OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = InvoiceDeliveryDF.CompNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = InvoiceDeliveryDF.VouYear AND 
                         OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = InvoiceDeliveryDF.VouNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = InvoiceDeliveryDF.VouType AND 
                         OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo = InvoiceDeliveryDF.ItemNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.BatchNo = InvoiceDeliveryDF.BatchNo AND 
                         OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode = InvoiceDeliveryDF.UnitCode
WHERE        (InvoiceDeliveryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) -- AND (ISNULL(InvoiceDeliveryHF.IsDelivered, 0) = 0)
 --AND (InvoiceDeliveryHF.DeliveredSalesmanNo = @SalesmanNo)
ORDER BY InvoiceDeliveryHF.VouDate	



	End


else if @ClientActive=132
	Begin
	print 'aaaa'
	select 0
	end


else
	Begin
	
	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo 
	WHERE        (OSFA_DB.dbo.OT_CustomerMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 


	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryDF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear AND OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType
	WHERE        (OSFA_DB.dbo.OT_CustomerMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
	
	INSERT INTO [OSFA_DB].[dbo].OT_InvoiceHistoryHF
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[VouDate]
			   ,[StoreNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]           
			   ,[VouDiscPerc]
				,[CustomerDiscPerc]
				,[Notes]
				,[IsForDelivery]
				,[SalesmanName],Ref1)
	SELECT        InvoiceDeliveryHF.CompNo, InvoiceDeliveryHF.VouYear, InvoiceDeliveryHF.VouNo, InvoiceDeliveryHF.VouType, InvoiceDeliveryHF.VouDate, 0 AS Expr2, InvoiceDeliveryHF.SalesmanNo, InvoiceDeliveryHF.CustomerNo, 
							 InvoiceDeliveryHF.VouDiscPerc, InvoiceDeliveryHF.CustomerDiscPerc, InvoiceDeliveryHF.Notes, 1 AS Expr1, SalesPersons.Name,InvoiceDeliveryHF.[PaymentTypeID]
	FROM            InvoiceDeliveryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceDeliveryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND InvoiceDeliveryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
							 SalesPersons ON InvoiceDeliveryHF.SalesmanNo = SalesPersons.ID AND InvoiceDeliveryHF.CompNo = SalesPersons.CompanyID LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON InvoiceDeliveryHF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND InvoiceDeliveryHF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND 
							 InvoiceDeliveryHF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND InvoiceDeliveryHF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType
	WHERE        (InvoiceDeliveryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (ISNULL(InvoiceDeliveryHF.IsDelivered, 0) = 0) 
							 AND (InvoiceDeliveryHF.DeliveredSalesmanNo = @SalesmanNo)
	ORDER BY InvoiceDeliveryHF.VouDate
	
	      
	INSERT INTO [OSFA_DB].[dbo].OT_InvoiceHistoryDF
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[ItemNo]
			   ,[BatchNo]
			   ,[UnitCode]
			   ,[Qty]
			   ,[Bonus]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[ItemDesc]
			   ,TaxType
			   ,[UnitPrice])
SELECT        InvoiceDeliveryDF.CompNo, InvoiceDeliveryDF.VouYear, InvoiceDeliveryDF.VouNo, InvoiceDeliveryDF.VouType, InvoiceDeliveryDF.ItemNo, InvoiceDeliveryDF.BatchNo, InvoiceDeliveryDF.UnitCode, InvoiceDeliveryDF.Qty, 
                         InvoiceDeliveryDF.Bonus, InvoiceDeliveryDF.SellValue, InvoiceDeliveryDF.DiscPerc, InvoiceDeliveryDF.DiscValue, InvoiceDeliveryDF.TaxPerc, InvoiceDeliveryDF.TaxValue, InvoiceDeliveryDF.ItemDesc, 
                         OSFA_DB.dbo.OT_InvoiceHistoryDF.TaxType, OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitPrice
FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF RIGHT OUTER JOIN
                         InvoiceDeliveryHF INNER JOIN
                         InvoiceDeliveryDF ON InvoiceDeliveryHF.CompNo = InvoiceDeliveryDF.CompNo AND InvoiceDeliveryHF.VouYear = InvoiceDeliveryDF.VouYear AND InvoiceDeliveryHF.VouNo = InvoiceDeliveryDF.VouNo AND 
                         InvoiceDeliveryHF.VouType = InvoiceDeliveryDF.VouType INNER JOIN
                         OSFA_DB.dbo.OT_CustomerMF ON InvoiceDeliveryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND InvoiceDeliveryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo ON 
                         OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = InvoiceDeliveryDF.CompNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = InvoiceDeliveryDF.VouYear AND 
                         OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = InvoiceDeliveryDF.VouNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = InvoiceDeliveryDF.VouType AND 
                         OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo = InvoiceDeliveryDF.ItemNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.BatchNo = InvoiceDeliveryDF.BatchNo AND 
                         OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode = InvoiceDeliveryDF.UnitCode
WHERE        (InvoiceDeliveryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)  AND (ISNULL(InvoiceDeliveryHF.IsDelivered, 0) = 0) AND (InvoiceDeliveryHF.DeliveredSalesmanNo = @SalesmanNo)
ORDER BY InvoiceDeliveryHF.VouDate	
     end
	                  
END


SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'UseInvoiceDelivery, OT_InvoiceHistoryHF, OT_InvoiceHistoryDF  [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')


-- -- - InvoiceHistory --------
IF @UseInvoiceDelivery = 0
BEGIN
if @ClientActive =19 OR @ClientActive =1 OR @ClientActive = 5 OR @ClientActive = 16 OR @ClientActive = 45 OR @ClientActive = 54 OR @ClientActive = 30 or @ClientActive = 63 
or @ClientActive=32 or @ClientActive=123 or (@ClientActive=85 AND @SalesmanGroupID<>4) OR @ClientActive = 149 or @ClientActive=13 and @CompNo=1 or @ClientActive=176

Begin 

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)


	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryHF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[VouDate]
			   ,[StoreNo]
			   ,[SalesmanNo]
			   ,[CustomerNo])
	SELECT        InvoiceHistoryHF.CompNo, InvoiceHistoryHF.VouYear, InvoiceHistoryHF.VouNo, InvoiceHistoryHF.VouType, InvoiceHistoryHF.VouDate, InvoiceHistoryHF.StoreNo, 
							 InvoiceHistoryHF.SalesmanNo, InvoiceHistoryHF.CustomerNo
	FROM            InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 InvoiceHistoryHF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND InvoiceHistoryHF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 InvoiceHistoryHF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL) AND 
							 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
							 order by InvoiceHistoryHF.VouDate
	
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

    SET @BeginTime = Convert(varchar(20),GetDate(),108) 
	             
	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryDF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[ItemNo]
			   ,[BatchNo]
			   ,[UnitCode]
			   ,[Qty]
			   ,[Bonus]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[ItemDesc],TaxType)
	SELECT        InvoiceHistoryDF.CompNo, InvoiceHistoryDF.VouYear, InvoiceHistoryDF.VouNo, InvoiceHistoryDF.VouType, InvoiceHistoryDF.ItemNo, InvoiceHistoryDF.BatchNo, 
							 InvoiceHistoryDF.UnitCode, InvoiceHistoryDF.Qty, InvoiceHistoryDF.Bonus, InvoiceHistoryDF.SellValue, InvoiceHistoryDF.DiscPerc, InvoiceHistoryDF.DiscValue, 
							 InvoiceHistoryDF.TaxPerc, InvoiceHistoryDF.TaxValue, InvoiceHistoryDF.ItemDesc,1
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF RIGHT OUTER JOIN
							 InvoiceHistoryHF INNER JOIN
							 InvoiceHistoryDF ON InvoiceHistoryHF.CompNo = InvoiceHistoryDF.CompNo AND InvoiceHistoryHF.VouYear = InvoiceHistoryDF.VouYear AND 
							 InvoiceHistoryHF.VouNo = InvoiceHistoryDF.VouNo AND InvoiceHistoryHF.VouType = InvoiceHistoryDF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND 
							 InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = InvoiceHistoryDF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = InvoiceHistoryDF.VouYear AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = InvoiceHistoryDF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = InvoiceHistoryDF.VouType AND OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo = InvoiceHistoryDF.ItemNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.BatchNo = InvoiceHistoryDF.BatchNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode = InvoiceHistoryDF.UnitCode
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)   
    order by InvoiceHistoryHF.VouDate

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'InvoiceHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

END

Else if @ClientActive=165--GCI
Begin


	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
	and OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType=3

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
	and OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType=3

INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryHF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[VouDate]
			   ,[StoreNo]
			   ,[SalesmanNo]
			   ,[CustomerNo])
	SELECT        InvoiceHistoryHF.CompNo, InvoiceHistoryHF.VouYear, InvoiceHistoryHF.VouNo, InvoiceHistoryHF.VouType, InvoiceHistoryHF.VouDate, InvoiceHistoryHF.StoreNo, 
							 InvoiceHistoryHF.SalesmanNo, InvoiceHistoryHF.CustomerNo
	FROM            InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 InvoiceHistoryHF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND InvoiceHistoryHF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 InvoiceHistoryHF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL) AND 
							 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) and InvoiceHistoryHF.VouType=3
							 order by InvoiceHistoryHF.VouDate
INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryDF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[ItemNo]
			   ,[BatchNo]
			   ,[UnitCode]
			   ,[Qty]
			   ,[Bonus]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[ItemDesc],TaxType)
	SELECT        InvoiceHistoryDF.CompNo, InvoiceHistoryDF.VouYear, InvoiceHistoryDF.VouNo, InvoiceHistoryDF.VouType, InvoiceHistoryDF.ItemNo, InvoiceHistoryDF.BatchNo, 
							 InvoiceHistoryDF.UnitCode, InvoiceHistoryDF.Qty, InvoiceHistoryDF.Bonus, InvoiceHistoryDF.SellValue, InvoiceHistoryDF.DiscPerc, InvoiceHistoryDF.DiscValue, 
							 InvoiceHistoryDF.TaxPerc, InvoiceHistoryDF.TaxValue, InvoiceHistoryDF.ItemDesc,1
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF RIGHT OUTER JOIN
							 InvoiceHistoryHF INNER JOIN
							 InvoiceHistoryDF ON InvoiceHistoryHF.CompNo = InvoiceHistoryDF.CompNo AND InvoiceHistoryHF.VouYear = InvoiceHistoryDF.VouYear AND 
							 InvoiceHistoryHF.VouNo = InvoiceHistoryDF.VouNo AND InvoiceHistoryHF.VouType = InvoiceHistoryDF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND 
							 InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = InvoiceHistoryDF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = InvoiceHistoryDF.VouYear AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = InvoiceHistoryDF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = InvoiceHistoryDF.VouType AND OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo = InvoiceHistoryDF.ItemNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.BatchNo = InvoiceHistoryDF.BatchNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode = InvoiceHistoryDF.UnitCode
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL) 
	AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)  and InvoiceHistoryDF.VouType=3 
    order by InvoiceHistoryHF.VouDate
END


Else if @ClientActive=117 and @CompNo=2
Begin 

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)


	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryHF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[VouDate]
			   ,[StoreNo]
			   ,[SalesmanNo]
			   ,[CustomerNo])
	SELECT        InvoiceHistoryHF.CompNo, InvoiceHistoryHF.VouYear, InvoiceHistoryHF.VouNo, InvoiceHistoryHF.VouType, InvoiceHistoryHF.VouDate, InvoiceHistoryHF.StoreNo, 
							 InvoiceHistoryHF.SalesmanNo, InvoiceHistoryHF.CustomerNo
	FROM            InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 InvoiceHistoryHF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND InvoiceHistoryHF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 InvoiceHistoryHF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL) AND 
							 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
							 order by InvoiceHistoryHF.VouDate
	
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

    SET @BeginTime = Convert(varchar(20),GetDate(),108) 
	             
	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryDF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[ItemNo]
			   ,[BatchNo]
			   ,[UnitCode]
			   ,[Qty]
			   ,[Bonus]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[ItemDesc],TaxType,UnitPrice)

	SELECT        InvoiceHistoryDF.CompNo, InvoiceHistoryDF.VouYear, InvoiceHistoryDF.VouNo, InvoiceHistoryDF.VouType, InvoiceHistoryDF.ItemNo, InvoiceHistoryDF.BatchNo, 
							 InvoiceHistoryDF.UnitCode, InvoiceHistoryDF.Qty, 0 as Bonus , InvoiceHistoryDF.SellValue, InvoiceHistoryDF.DiscPerc, InvoiceHistoryDF.DiscValue, 
							 InvoiceHistoryDF.TaxPerc, InvoiceHistoryDF.TaxValue, InvoiceHistoryDF.ItemDesc,1 ,case when InvoiceHistoryDF.bonus>0 then InvoiceHistoryDF.SellValue /
							 (InvoiceHistoryDF.Qty+InvoiceHistoryDF.bonus) else  InvoiceHistoryDF.UnitPrice end  as Uniprice
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF RIGHT OUTER JOIN
							 InvoiceHistoryHF INNER JOIN
							 InvoiceHistoryDF ON InvoiceHistoryHF.CompNo = InvoiceHistoryDF.CompNo AND InvoiceHistoryHF.VouYear = InvoiceHistoryDF.VouYear AND 
							 InvoiceHistoryHF.VouNo = InvoiceHistoryDF.VouNo AND InvoiceHistoryHF.VouType = InvoiceHistoryDF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND 
							 InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = InvoiceHistoryDF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = InvoiceHistoryDF.VouYear AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = InvoiceHistoryDF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = InvoiceHistoryDF.VouType AND OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo = InvoiceHistoryDF.ItemNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.BatchNo = InvoiceHistoryDF.BatchNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode = InvoiceHistoryDF.UnitCode
WHERE  (InvoiceHistoryHF.CompNo = @compno) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL) AND
(OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @salesmanno)   
order by InvoiceHistoryHF.VouDate
/*---Old Original Query for AbnaSukhtian
	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryDF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[ItemNo]
			   ,[BatchNo]
			   ,[UnitCode]
			   ,[Qty]
			   ,[Bonus]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[ItemDesc],TaxType,UnitPrice)

	SELECT        InvoiceHistoryDF.CompNo, InvoiceHistoryDF.VouYear, InvoiceHistoryDF.VouNo, InvoiceHistoryDF.VouType, InvoiceHistoryDF.ItemNo, InvoiceHistoryDF.BatchNo, 
							 InvoiceHistoryDF.UnitCode, InvoiceHistoryDF.Qty, InvoiceHistoryDF.Bonus, InvoiceHistoryDF.SellValue, InvoiceHistoryDF.DiscPerc, InvoiceHistoryDF.DiscValue, 
							 InvoiceHistoryDF.TaxPerc, InvoiceHistoryDF.TaxValue, InvoiceHistoryDF.ItemDesc,1 ,InvoiceHistoryDF.UnitPrice
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF RIGHT OUTER JOIN
							 InvoiceHistoryHF INNER JOIN
							 InvoiceHistoryDF ON InvoiceHistoryHF.CompNo = InvoiceHistoryDF.CompNo AND InvoiceHistoryHF.VouYear = InvoiceHistoryDF.VouYear AND 
							 InvoiceHistoryHF.VouNo = InvoiceHistoryDF.VouNo AND InvoiceHistoryHF.VouType = InvoiceHistoryDF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND 
							 InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = InvoiceHistoryDF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = InvoiceHistoryDF.VouYear AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = InvoiceHistoryDF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = InvoiceHistoryDF.VouType AND OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo = InvoiceHistoryDF.ItemNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.BatchNo = InvoiceHistoryDF.BatchNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode = InvoiceHistoryDF.UnitCode
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)   
    order by InvoiceHistoryHF.VouDate
*/
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'InvoiceHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

END 


else if  @ClientActive=121 and @IsMakeOrderOnly=1
Begin
	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)


	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryHF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[VouDate]
			   ,[StoreNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[VouDiscPerc]
			   ,InvStatus
			    )
	SELECT        InvoiceHistoryHF.CompNo, InvoiceHistoryHF.VouYear, InvoiceHistoryHF.VouNo, InvoiceHistoryHF.VouType, InvoiceHistoryHF.VouDate, InvoiceHistoryHF.StoreNo, 
							 InvoiceHistoryHF.SalesmanNo, InvoiceHistoryHF.CustomerNo,ABS (InvoiceHistoryHF.VouDiscPerc ),InvoiceHistoryHF.InvStatus
	FROM            InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 InvoiceHistoryHF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND InvoiceHistoryHF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 InvoiceHistoryHF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL) AND 
							 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
							 order by InvoiceHistoryHF.VouDate
	
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

    SET @BeginTime = Convert(varchar(20),GetDate(),108) 
	            
	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryDF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[ItemNo]
			   ,[BatchNo]
			   ,[UnitCode]
			   ,[Qty]
			   ,[Bonus]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[ItemDesc],
			   [TaxType] , 
			   [UnitPrice],
			   VouDiscValue)
	SELECT        InvoiceHistoryDF.CompNo, InvoiceHistoryDF.VouYear, InvoiceHistoryDF.VouNo, InvoiceHistoryDF.VouType, InvoiceHistoryDF.ItemNo, InvoiceHistoryDF.BatchNo, 
							 InvoiceHistoryDF.UnitCode, InvoiceHistoryDF.Qty, InvoiceHistoryDF.Bonus,  (InvoiceHistoryDF.SellValue) as SellValue, InvoiceHistoryDF.DiscPerc, 
							 ABS (InvoiceHistorydF.DiscValue ), 
							 InvoiceHistoryDF.TaxPerc, InvoiceHistoryDF.TaxValue, InvoiceHistoryDF.ItemDesc,1 ,  case when InvoiceHistoryDF.Qty>0 then
							 (InvoiceHistoryDF.SellValue-InvoiceHistoryDF.TaxValue)/InvoiceHistoryDF.Qty else 0 end as UPrice
							 ,0
		FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF RIGHT OUTER JOIN
							 InvoiceHistoryHF INNER JOIN
							 InvoiceHistoryDF ON InvoiceHistoryHF.CompNo = InvoiceHistoryDF.CompNo AND InvoiceHistoryHF.VouYear = InvoiceHistoryDF.VouYear AND 
							 InvoiceHistoryHF.VouNo = InvoiceHistoryDF.VouNo AND InvoiceHistoryHF.VouType = InvoiceHistoryDF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND 
							 InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = InvoiceHistoryDF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = InvoiceHistoryDF.VouYear AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = InvoiceHistoryDF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = InvoiceHistoryDF.VouType AND OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo = InvoiceHistoryDF.ItemNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.BatchNo = InvoiceHistoryDF.BatchNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode = InvoiceHistoryDF.UnitCode
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)   
    order by InvoiceHistoryHF.VouDate

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'InvoiceHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

END

else if  @ClientActive=100
Begin 

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)


	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryHF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[VouDate]
			   ,[StoreNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[VouDiscPerc])
	SELECT        InvoiceHistoryHF.CompNo, InvoiceHistoryHF.VouYear, InvoiceHistoryHF.VouNo, InvoiceHistoryHF.VouType, InvoiceHistoryHF.VouDate, InvoiceHistoryHF.StoreNo, 
							 InvoiceHistoryHF.SalesmanNo, InvoiceHistoryHF.CustomerNo,InvoiceHistoryHF.VouDiscPerc
	FROM            InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 InvoiceHistoryHF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND InvoiceHistoryHF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 InvoiceHistoryHF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL) AND 
							 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
							 order by InvoiceHistoryHF.VouDate
	
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

    SET @BeginTime = Convert(varchar(20),GetDate(),108) 
	             
	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryDF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[ItemNo]
			   ,[BatchNo]
			   ,[UnitCode]
			   ,[Qty]
			   ,[Bonus]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[ItemDesc],TaxType)
	SELECT        InvoiceHistoryDF.CompNo, InvoiceHistoryDF.VouYear, InvoiceHistoryDF.VouNo, InvoiceHistoryDF.VouType, InvoiceHistoryDF.ItemNo, InvoiceHistoryDF.BatchNo, 
							 InvoiceHistoryDF.UnitCode, InvoiceHistoryDF.Qty, InvoiceHistoryDF.Bonus, InvoiceHistoryDF.SellValue, InvoiceHistoryDF.DiscPerc, InvoiceHistoryDF.DiscValue, 
							 InvoiceHistoryDF.TaxPerc, InvoiceHistoryDF.TaxValue, InvoiceHistoryDF.ItemDesc,1
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF RIGHT OUTER JOIN
							 InvoiceHistoryHF INNER JOIN
							 InvoiceHistoryDF ON InvoiceHistoryHF.CompNo = InvoiceHistoryDF.CompNo AND InvoiceHistoryHF.VouYear = InvoiceHistoryDF.VouYear AND 
							 InvoiceHistoryHF.VouNo = InvoiceHistoryDF.VouNo AND InvoiceHistoryHF.VouType = InvoiceHistoryDF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND 
							 InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = InvoiceHistoryDF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = InvoiceHistoryDF.VouYear AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = InvoiceHistoryDF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = InvoiceHistoryDF.VouType AND OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo = InvoiceHistoryDF.ItemNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.BatchNo = InvoiceHistoryDF.BatchNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode = InvoiceHistoryDF.UnitCode
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)   
    order by InvoiceHistoryHF.VouDate

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'InvoiceHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

END 

Else if  @ClientActive=144 
Begin 

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)


	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

INSERT INTO OSFA_DB.[dbo].[OT_InvoiceHistoryHF]
           ([CompNo]
           ,[VouYear]
           ,[VouNo]
           ,[VouType]
           ,[VouDate]
           ,[StoreNo]
           ,[SalesmanNo]
           ,[CustomerNo]
           ,[VouDiscPerc]
           ,[CustomerDiscPerc]
           ,[InvStatus]
		   ,Ref1
)

	SELECT    distinct    InvoiceHistoryHF.CompNo, InvoiceHistoryHF.VouYear, InvoiceHistoryHF.VouNo, InvoiceHistoryHF.VouType, InvoiceHistoryHF.VouDate, InvoiceHistoryHF.StoreNo, 
							 InvoiceHistoryHF.SalesmanNo, InvoiceHistoryHF.CustomerNo , InvoiceHistoryHF.VouDiscPerc ,InvoiceHistoryHF.CustomerDiscPerc , InvoiceHistoryHF.InvStatus,
							 InvoiceHistoryHF.ERPVouNo
	FROM            InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 InvoiceHistoryHF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND InvoiceHistoryHF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 InvoiceHistoryHF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL) AND 
							 (InvoiceHistoryHF.SalesmanNo = @SalesmanNo)
							 order by InvoiceHistoryHF.VouDate
	
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

    SET @BeginTime = Convert(varchar(20),GetDate(),108) 
	             
	INSERT INTO OSFA_DB.[dbo].[OT_InvoiceHistoryDF]
           ([CompNo]
           ,[VouYear]
           ,[VouNo]
           ,[VouType]
           ,[ItemNo]
           ,[BatchNo]
           ,[UnitCode]
           ,[Qty]
           ,[Bonus]
           ,[SellValue]
           ,[DiscPerc]
           ,[DiscValue]
           ,[TaxPerc]
           ,[TaxValue]
           ,[ItemDesc]
           ,[TaxType]
  )

	SELECT        InvoiceHistoryDF.CompNo, InvoiceHistoryDF.VouYear, InvoiceHistoryDF.VouNo, InvoiceHistoryDF.VouType, InvoiceHistoryDF.ItemNo, InvoiceHistoryDF.BatchNo, 
							 InvoiceHistoryDF.UnitCode, InvoiceHistoryDF.Qty, InvoiceHistoryDF.Bonus, InvoiceHistoryDF.SellValue, InvoiceHistoryDF.DiscPerc, InvoiceHistoryDF.DiscValue, 
							 InvoiceHistoryDF.TaxPerc, InvoiceHistoryDF.TaxValue, InvoiceHistoryDF.ItemDesc,1
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF RIGHT OUTER JOIN
							 InvoiceHistoryHF INNER JOIN
							 InvoiceHistoryDF ON InvoiceHistoryHF.CompNo = InvoiceHistoryDF.CompNo AND InvoiceHistoryHF.VouYear = InvoiceHistoryDF.VouYear AND 
							 InvoiceHistoryHF.VouNo = InvoiceHistoryDF.VouNo AND InvoiceHistoryHF.VouType = InvoiceHistoryDF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND 
							 InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = InvoiceHistoryDF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = InvoiceHistoryDF.VouYear AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = InvoiceHistoryDF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = InvoiceHistoryDF.VouType AND OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo = InvoiceHistoryDF.ItemNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.BatchNo = InvoiceHistoryDF.BatchNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode = InvoiceHistoryDF.UnitCode
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)   
    order by InvoiceHistoryHF.VouDate

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'InvoiceHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

END 


Else if @ClientActive=111 
Begin 

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)


	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

INSERT INTO OSFA_DB.[dbo].[OT_InvoiceHistoryHF]
           ([CompNo]
           ,[VouYear]
           ,[VouNo]
           ,[VouType]
           ,[VouDate]
           ,[StoreNo]
           ,[SalesmanNo]
           ,[CustomerNo]
           ,[VouDiscPerc]
           ,[CustomerDiscPerc]
           ,[InvStatus]
		   ,Ref1
)

	SELECT        InvoiceHistoryHF.CompNo, InvoiceHistoryHF.VouYear, InvoiceHistoryHF.VouNo, InvoiceHistoryHF.VouType, InvoiceHistoryHF.VouDate, InvoiceHistoryHF.StoreNo, 
							 @SalesmanNo, InvoiceHistoryHF.CustomerNo , InvoiceHistoryHF.VouDiscPerc ,InvoiceHistoryHF.CustomerDiscPerc , InvoiceHistoryHF.InvStatus,
							 InvoiceHistoryHF.ERPVouNo
	FROM            InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 InvoiceHistoryHF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND InvoiceHistoryHF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 InvoiceHistoryHF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND --(OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL) AND 
							 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
							 order by InvoiceHistoryHF.VouDate
	
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

    SET @BeginTime = Convert(varchar(20),GetDate(),108) 
	             
	INSERT INTO OSFA_DB.[dbo].[OT_InvoiceHistoryDF]
           ([CompNo]
           ,[VouYear]
           ,[VouNo]
           ,[VouType]
           ,[ItemNo]
           ,[BatchNo]
           ,[UnitCode]
           ,[Qty]
           ,[Bonus]
           ,[SellValue]
           ,[DiscPerc]
           ,[DiscValue]
           ,[TaxPerc]
           ,[TaxValue]
           ,[ItemDesc]
           ,[TaxType]
  )

	SELECT        InvoiceHistoryDF.CompNo, InvoiceHistoryDF.VouYear, InvoiceHistoryDF.VouNo, InvoiceHistoryDF.VouType, InvoiceHistoryDF.ItemNo, InvoiceHistoryDF.BatchNo, 
							 InvoiceHistoryDF.UnitCode, InvoiceHistoryDF.Qty, InvoiceHistoryDF.Bonus, InvoiceHistoryDF.SellValue, InvoiceHistoryDF.DiscPerc, InvoiceHistoryDF.DiscValue, 
							 InvoiceHistoryDF.TaxPerc, InvoiceHistoryDF.TaxValue, InvoiceHistoryDF.ItemDesc,1
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF RIGHT OUTER JOIN
							 InvoiceHistoryHF INNER JOIN
							 InvoiceHistoryDF ON InvoiceHistoryHF.CompNo = InvoiceHistoryDF.CompNo AND InvoiceHistoryHF.VouYear = InvoiceHistoryDF.VouYear AND 
							 InvoiceHistoryHF.VouNo = InvoiceHistoryDF.VouNo AND InvoiceHistoryHF.VouType = InvoiceHistoryDF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND 
							 InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = InvoiceHistoryDF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = InvoiceHistoryDF.VouYear AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = InvoiceHistoryDF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = InvoiceHistoryDF.VouType AND OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo = InvoiceHistoryDF.ItemNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.BatchNo = InvoiceHistoryDF.BatchNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode = InvoiceHistoryDF.UnitCode
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)   
    order by InvoiceHistoryHF.VouDate

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'InvoiceHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

END 
else if @ClientActive=91
Begin 
print'91'

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)


	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryHF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[VouDate]
			   ,[StoreNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[VouDiscPerc]
			    )
	SELECT        InvoiceHistoryHF.CompNo, InvoiceHistoryHF.VouYear, InvoiceHistoryHF.VouNo, InvoiceHistoryHF.VouType, InvoiceHistoryHF.VouDate, InvoiceHistoryHF.StoreNo, 
							 InvoiceHistoryHF.SalesmanNo, InvoiceHistoryHF.CustomerNo,--ABS (InvoiceHistoryHF.VouDiscPerc ),
							 0 as  VouDiscPerc
	FROM            InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 InvoiceHistoryHF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND InvoiceHistoryHF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 InvoiceHistoryHF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL) AND 
							 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
							 order by InvoiceHistoryHF.VouDate
	
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

    SET @BeginTime = Convert(varchar(20),GetDate(),108) 
	            
	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryDF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[ItemNo]
			   ,[BatchNo]
			   ,[UnitCode]
			   ,[Qty]
			   ,[Bonus]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[ItemDesc],
			   [TaxType] , 
			   [UnitPrice])
	SELECT        InvoiceHistoryDF.CompNo, InvoiceHistoryDF.VouYear, InvoiceHistoryDF.VouNo, InvoiceHistoryDF.VouType, InvoiceHistoryDF.ItemNo, InvoiceHistoryDF.BatchNo, 
							 InvoiceHistoryDF.UnitCode, abs(InvoiceHistoryDF.Qty), InvoiceHistoryDF.Bonus,  abs(InvoiceHistoryDF.SellValue) as SellValue, 
							 0 as DiscPerc, 	--ABS (InvoiceHistorydF.DiscValue )
							 0 as DiscValue, 
							 InvoiceHistoryDF.TaxPerc, InvoiceHistoryDF.TaxValue, InvoiceHistoryDF.ItemDesc
							 ,1 ,  case when abs(InvoiceHistoryDF.Qty)>0 then (abs(InvoiceHistoryDF.SellValue)-InvoiceHistoryDF.TaxValue)/abs(InvoiceHistoryDF.Qty) else 0 end as UPrice
						
		FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF RIGHT OUTER JOIN
							 InvoiceHistoryHF INNER JOIN
							 InvoiceHistoryDF ON InvoiceHistoryHF.CompNo = InvoiceHistoryDF.CompNo AND InvoiceHistoryHF.VouYear = InvoiceHistoryDF.VouYear AND 
							 InvoiceHistoryHF.VouNo = InvoiceHistoryDF.VouNo AND InvoiceHistoryHF.VouType = InvoiceHistoryDF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND 
							 InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = InvoiceHistoryDF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = InvoiceHistoryDF.VouYear AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = InvoiceHistoryDF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = InvoiceHistoryDF.VouType AND OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo = InvoiceHistoryDF.ItemNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.BatchNo = InvoiceHistoryDF.BatchNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode = InvoiceHistoryDF.UnitCode
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)   
    order by InvoiceHistoryHF.VouDate

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'InvoiceHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

END  


else if @ClientActive =84 or @ClientActive=107 OR @ClientActive =27 or @ClientActive=92
Begin 
print'84'

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)


	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryHF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[VouDate]
			   ,[StoreNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[VouDiscPerc]
			    )
	SELECT        InvoiceHistoryHF.CompNo, InvoiceHistoryHF.VouYear, InvoiceHistoryHF.VouNo, InvoiceHistoryHF.VouType, InvoiceHistoryHF.VouDate, InvoiceHistoryHF.StoreNo, 
							 InvoiceHistoryHF.SalesmanNo, InvoiceHistoryHF.CustomerNo,ABS (InvoiceHistoryHF.VouDiscPerc )
	FROM            InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 InvoiceHistoryHF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND InvoiceHistoryHF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 InvoiceHistoryHF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL) AND 
							 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
							 order by InvoiceHistoryHF.VouDate
	
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

    SET @BeginTime = Convert(varchar(20),GetDate(),108) 
	            
	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryDF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[ItemNo]
			   ,[BatchNo]
			   ,[UnitCode]
			   ,[Qty]
			   ,[Bonus]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[ItemDesc],
			   [TaxType] , 
			   [UnitPrice],
			   VouDiscValue)
	SELECT        InvoiceHistoryDF.CompNo, InvoiceHistoryDF.VouYear, InvoiceHistoryDF.VouNo, InvoiceHistoryDF.VouType, InvoiceHistoryDF.ItemNo, InvoiceHistoryDF.BatchNo, 
							 InvoiceHistoryDF.UnitCode, InvoiceHistoryDF.Qty, InvoiceHistoryDF.Bonus,  (InvoiceHistoryDF.SellValue) as SellValue, InvoiceHistoryDF.DiscPerc, 0, 
							 InvoiceHistoryDF.TaxPerc, InvoiceHistoryDF.TaxValue, InvoiceHistoryDF.ItemDesc,1 ,  case when InvoiceHistoryDF.Qty>0 then (InvoiceHistoryDF.SellValue-InvoiceHistoryDF.TaxValue)/InvoiceHistoryDF.Qty else 0 end as UPrice
							 ,ABS (InvoiceHistorydF.DiscValue )
		FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF RIGHT OUTER JOIN
							 InvoiceHistoryHF INNER JOIN
							 InvoiceHistoryDF ON InvoiceHistoryHF.CompNo = InvoiceHistoryDF.CompNo AND InvoiceHistoryHF.VouYear = InvoiceHistoryDF.VouYear AND 
							 InvoiceHistoryHF.VouNo = InvoiceHistoryDF.VouNo AND InvoiceHistoryHF.VouType = InvoiceHistoryDF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND 
							 InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = InvoiceHistoryDF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = InvoiceHistoryDF.VouYear AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = InvoiceHistoryDF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = InvoiceHistoryDF.VouType AND OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo = InvoiceHistoryDF.ItemNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.BatchNo = InvoiceHistoryDF.BatchNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode = InvoiceHistoryDF.UnitCode
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)   
    order by InvoiceHistoryHF.VouDate

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'InvoiceHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

END 

else if @ClientActive=109
begin
select 0
end


else if  @ClientActive = 67
Begin 
	set @AccStatDays =-60
	set @AccStatFromDate = GETDATE()
	SET @AccStatFromDate=DATEADD(DAY,@AccStatDays,@SendDate)
	
	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)


	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
	   
	
	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryHF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[VouDate]
			   ,[StoreNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[InvStatus]
			   ,[Notes]
			   )

			
	SELECT        InvoiceHistoryHF.CompNo, InvoiceHistoryHF.VouYear, InvoiceHistoryHF.VouNo, InvoiceHistoryHF.VouType, InvoiceHistoryHF.VouDate, InvoiceHistoryHF.StoreNo, 
							 InvoiceHistoryHF.SalesmanNo, InvoiceHistoryHF.CustomerNo,InvoiceHistoryHF.InvStatus,InvoiceHistoryHF.Notes
	FROM            InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 InvoiceHistoryHF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND InvoiceHistoryHF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 InvoiceHistoryHF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) /*AND (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL)*/ AND 
							 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) and (InvoiceHistoryHF.VouDate > @AccStatFromDate)
							 order by InvoiceHistoryHF.VouDate
	
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

    SET @BeginTime = Convert(varchar(20),GetDate(),108) 
	             
	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryDF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[ItemNo]
			   ,[BatchNo]
			   ,[UnitCode]
			   ,[Qty]
			   ,[Bonus]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[ItemDesc])
	--SELECT        InvoiceHistoryDF.CompNo, InvoiceHistoryDF.VouYear, InvoiceHistoryDF.VouNo, InvoiceHistoryDF.VouType, InvoiceHistoryDF.ItemNo, InvoiceHistoryDF.BatchNo, 
	--						 InvoiceHistoryDF.UnitCode, InvoiceHistoryDF.Qty, InvoiceHistoryDF.Bonus, InvoiceHistoryDF.SellValue, InvoiceHistoryDF.DiscPerc, InvoiceHistoryDF.DiscValue, 
	--						 InvoiceHistoryDF.TaxPerc, InvoiceHistoryDF.TaxValue, InvoiceHistoryDF.ItemDesc
	--FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF RIGHT OUTER JOIN
	--						 InvoiceHistoryHF INNER JOIN
	--						 InvoiceHistoryDF ON InvoiceHistoryHF.CompNo = InvoiceHistoryDF.CompNo AND InvoiceHistoryHF.VouYear = InvoiceHistoryDF.VouYear AND 
	--						 InvoiceHistoryHF.VouNo = InvoiceHistoryDF.VouNo AND InvoiceHistoryHF.VouType = InvoiceHistoryDF.VouType INNER JOIN
	--						 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND 
	--						 InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = InvoiceHistoryDF.CompNo AND 
	--						 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = InvoiceHistoryDF.VouYear AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = InvoiceHistoryDF.VouNo AND 
	--						 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = InvoiceHistoryDF.VouType AND OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo = InvoiceHistoryDF.ItemNo AND 
	--						 OSFA_DB.dbo.OT_InvoiceHistoryDF.BatchNo = InvoiceHistoryDF.BatchNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode = InvoiceHistoryDF.UnitCode
	--WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (InvoiceHistoryHF.VouDate > @AccStatFromDate)
 --   order by InvoiceHistoryHF.VouDate
 SELECT        InvoiceHistoryDF.CompNo, InvoiceHistoryDF.VouYear, InvoiceHistoryDF.VouNo, InvoiceHistoryDF.VouType, InvoiceHistoryDF.ItemNo, InvoiceHistoryDF.BatchNo, InvoiceHistoryDF.UnitCode, InvoiceHistoryDF.Qty, 
                         InvoiceHistoryDF.Bonus, InvoiceHistoryDF.SellValue, InvoiceHistoryDF.DiscPerc, InvoiceHistoryDF.DiscValue, InvoiceHistoryDF.TaxPerc, InvoiceHistoryDF.TaxValue, InvoiceHistoryDF.ItemDesc
FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF RIGHT OUTER JOIN
                         InvoiceHistoryHF INNER JOIN
                         InvoiceHistoryDF ON InvoiceHistoryHF.CompNo = InvoiceHistoryDF.CompNo AND InvoiceHistoryHF.VouYear = InvoiceHistoryDF.VouYear AND InvoiceHistoryHF.VouNo = InvoiceHistoryDF.VouNo AND 
                         InvoiceHistoryHF.VouType = InvoiceHistoryDF.VouType ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = InvoiceHistoryDF.CompNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = InvoiceHistoryDF.VouYear AND 
                         OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = InvoiceHistoryDF.VouNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = InvoiceHistoryDF.VouType AND 
                         OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo = InvoiceHistoryDF.ItemNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.BatchNo = InvoiceHistoryDF.BatchNo AND 
                         OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode = InvoiceHistoryDF.UnitCode
WHERE        (InvoiceHistoryHF.CompNo =@CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL) AND (InvoiceHistoryHF.VouDate > @AccStatFromDate) 
and InvoiceHistoryHF.CustomerNo in (select customerno from OSFA_DB..ot_customerMF where SalesmanNo=@SalesmanNo and CompNo=@CompNo)
ORDER BY InvoiceHistoryHF.VouDate

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'InvoiceHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
END



else if @ClientActive=74  or @ClientActive = 17
Begin 
	set @AccStatDays =-60
	set @AccStatFromDate = GETDATE()
	SET @AccStatFromDate=DATEADD(DAY,@AccStatDays,@SendDate)
	
	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)


	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
	   
	
	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryHF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[VouDate]
			   ,[StoreNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[InvStatus]
			   ,[Notes]
			   )

			
	SELECT        InvoiceHistoryHF.CompNo, InvoiceHistoryHF.VouYear, InvoiceHistoryHF.VouNo, InvoiceHistoryHF.VouType, InvoiceHistoryHF.VouDate, InvoiceHistoryHF.StoreNo, 
							 InvoiceHistoryHF.SalesmanNo, InvoiceHistoryHF.CustomerNo,InvoiceHistoryHF.InvStatus,InvoiceHistoryHF.Notes
	FROM            InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 InvoiceHistoryHF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND InvoiceHistoryHF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 InvoiceHistoryHF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL) AND 
							 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) and (InvoiceHistoryHF.VouDate > @AccStatFromDate)
							 order by InvoiceHistoryHF.VouDate
	
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

    SET @BeginTime = Convert(varchar(20),GetDate(),108) 
	             
	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryDF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[ItemNo]
			   ,[BatchNo]
			   ,[UnitCode]
			   ,[Qty]
			   ,[Bonus]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[ItemDesc],TaxType)
	SELECT        InvoiceHistoryDF.CompNo, InvoiceHistoryDF.VouYear, InvoiceHistoryDF.VouNo, InvoiceHistoryDF.VouType, InvoiceHistoryDF.ItemNo, InvoiceHistoryDF.BatchNo, 
							 InvoiceHistoryDF.UnitCode, InvoiceHistoryDF.Qty, InvoiceHistoryDF.Bonus, InvoiceHistoryDF.SellValue, InvoiceHistoryDF.DiscPerc, InvoiceHistoryDF.DiscValue, 
							 InvoiceHistoryDF.TaxPerc, InvoiceHistoryDF.TaxValue, InvoiceHistoryDF.ItemDesc,1
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF RIGHT OUTER JOIN
							 InvoiceHistoryHF INNER JOIN
							 InvoiceHistoryDF ON InvoiceHistoryHF.CompNo = InvoiceHistoryDF.CompNo AND InvoiceHistoryHF.VouYear = InvoiceHistoryDF.VouYear AND 
							 InvoiceHistoryHF.VouNo = InvoiceHistoryDF.VouNo AND InvoiceHistoryHF.VouType = InvoiceHistoryDF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND 
							 InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = InvoiceHistoryDF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = InvoiceHistoryDF.VouYear AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = InvoiceHistoryDF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = InvoiceHistoryDF.VouType AND OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo = InvoiceHistoryDF.ItemNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.BatchNo = InvoiceHistoryDF.BatchNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode = InvoiceHistoryDF.UnitCode
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (InvoiceHistoryHF.VouDate > @AccStatFromDate)
    order by InvoiceHistoryHF.VouDate

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'InvoiceHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
END
ELSE IF @ClientActive =35
BEGIN

	--delete from  OSFA_DB.dbo.OT_InvoiceHistoryHF where CompNo=@CompNo and SalesmanNo =@SalesmanNo


	--INSERT INTO OSFA_DB.dbo.OT_InvoiceHistoryHF
	--					  (CompNo, VouYear, VouNo, VouType, SalesmanNo, CustomerNo, VouDate, StoreNo)
	--SELECT DISTINCT 
	--					  InvoiceHistoryHF.CompNo, InvoiceHistoryHF.VouYear, InvoiceHistoryHF.VouNo, InvoiceHistoryHF.VouType, InvoiceHistoryHF.SalesmanNo, 
	--					  InvoiceHistoryHF.CustomerNo, InvoiceHistoryHF.VouDate, 0 AS Expr1
	--FROM         InvoiceHistoryHF INNER JOIN
	--					  OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
	--					  InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND 
	--					  InvoiceHistoryHF.SalesmanNo = OSFA_DB.dbo.OT_CustomerMF.SalesmanNo
	--WHERE     (InvoiceHistoryHF.CompNo = @CompNo) AND (InvoiceHistoryHF.VouDate >= @SendDate) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

	delete from [OSFA_DB].[dbo].[OT_InvoiceHistoryHF]
	delete from [OSFA_DB].[dbo].[OT_InvoiceHistoryDF]

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryHF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[VouDate]
			   ,[StoreNo]
			   ,[SalesmanNo]
			   ,[CustomerNo])
	SELECT DISTINCT 
						  InvoiceHistoryHF.CompNo, InvoiceHistoryHF.VouYear, InvoiceHistoryHF.VouNo, InvoiceHistoryHF.VouType, InvoiceHistoryHF.VouDate, InvoiceHistoryHF.StoreNo, 
						  17 AS Expr1, InvoiceHistoryHF.CustomerNo
	FROM         InvoiceHistoryHF INNER JOIN
						  Customers ON InvoiceHistoryHF.CompNo = Customers.CompanyID AND InvoiceHistoryHF.CustomerNo = Customers.ID
	WHERE     (InvoiceHistoryHF.CompNo = @CompNo) AND (Customers.Reference1 <> N'new') and LEN([VouNo])<10  --and VouNo= 33276

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO   [OSFA_DB].[dbo].[OT_InvoiceHistoryDF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[ItemNo]
			   ,[BatchNo]
			   ,[UnitCode]
			   ,[Qty]
			   ,[Bonus]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[ItemDesc]
			   ,[Unitprice]
			    ,[taxtype])
	SELECT DISTINCT 
						  CompNo, VouYear, VouNo, VouType, ItemNo, BatchNo, UnitCode, Qty, Bonus, SellValue, DiscPerc, DiscValue, TaxPerc, TaxValue, ItemDesc, abs(UnitPrice), 
						  1 AS Expr1
	FROM         InvoiceHistoryDF
	WHERE     (CompNo = @CompNo) and LEN([VouNo])<10  --and VouNo= 33276

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'InvoiceHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

END


else  if @ClientActive =27 
Begin
Declare @CashCust as varchar(max)
SELECT  @CashCust = Op_Value FROM  OSFA_DB.dbo.OT_SystemOptions WHERE (CompNo = @CompNo) AND (Op_ID = 226) AND (SalesmanNo=0)
-- -- - InvoiceHistory --------
	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 TransactionsHeaders INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo ON 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = TransactionsHeaders.CompanyID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType = TransactionsHeaders.TransactionTypeID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear = TransactionsHeaders.TransactionYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo = TransactionsHeaders.TransactionNo
	WHERE        (TransactionsHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (TransactionsHeaders.TransactionTypeID in (1,2))

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            TransactionsDetails INNER JOIN
							 TransactionsHeaders ON TransactionsDetails.CompanyID = TransactionsHeaders.CompanyID AND 
							 TransactionsDetails.TransactionTypeID = TransactionsHeaders.TransactionTypeID AND 
							 TransactionsDetails.TransactionYear = TransactionsHeaders.TransactionYear AND 
							 TransactionsDetails.TransactionNo = TransactionsHeaders.TransactionNo INNER JOIN
							 Items ON TransactionsDetails.CompanyID = Items.CompanyID AND TransactionsDetails.ItemCode = Items.ItemCode INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryDF ON TransactionsDetails.CompanyID = OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo AND 
							 TransactionsDetails.TransactionYear = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear AND 
							 TransactionsDetails.TransactionNo = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo AND 
							 TransactionsDetails.TransactionTypeID = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType AND 
							 TransactionsDetails.ItemCode = OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo AND TransactionsDetails.UnitID = OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode
	WHERE        (TransactionsDetails.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (TransactionsHeaders.TransactionTypeID in (1,2))
	

	INSERT INTO OSFA_DB.dbo.OT_InvoiceHistoryHF (CompNo, VouYear, VouNo, VouType, VouDate, StoreNo, SalesmanNo, CustomerNo, VouDiscPerc, CustomerDiscPerc)
	SELECT    distinct    TransactionsHeaders.CompanyID, TransactionsHeaders.TransactionYear, TransactionsHeaders.TransactionNo, TransactionsHeaders.TransactionTypeID, 

							 TransactionsHeaders.TransactionDate, 0 AS Expr1, TransactionsHeaders.SalesPersonID, TransactionsHeaders.CustomerID, 
							 ABS(TransactionsHeaders.DiscountPercent) AS DiscountPercent, ABS(TransactionsHeaders.CustomerDiscountPerc) AS CustomerDiscountPerc
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF RIGHT OUTER JOIN
							 TransactionsHeaders INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo ON 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = TransactionsHeaders.CompanyID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType = TransactionsHeaders.TransactionTypeID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear = TransactionsHeaders.TransactionYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo = TransactionsHeaders.TransactionNo
							 LEFT OUTER JOIN [dbo].[Fun_ConvArrayToTable](@CashCust,',') AS i ON TransactionsHeaders.CustomerID = i.stringPart
	WHERE        (TransactionsHeaders.CompanyID = @CompNo) AND (TransactionsHeaders.TransactionDate BETWEEN @RetInvDate AND @SendDate) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND 
							 (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL) AND (TransactionsHeaders.TransactionTypeID in (1,2)) AND (i.stringPart IS NULL) 
   
    SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

    SET @BeginTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO OSFA_DB.dbo.OT_InvoiceHistoryDF
							 (CompNo, VouYear, VouNo, VouType, ItemNo, BatchNo, UnitCode, Qty, Bonus, SellValue, DiscPerc, DiscValue, TaxPerc, TaxValue, TaxType, ItemDesc,UnitPrice,VouDiscValue,CustDiscValue)
	SELECT     distinct   TransactionsDetails.CompanyID, TransactionsDetails.TransactionYear, TransactionsDetails.TransactionNo, TransactionsDetails.TransactionTypeID, 
							TransactionsDetails.ItemCode, '0' AS BatchNo, TransactionsDetails.UnitID, ABS(dbo.GetItemOrgUnitQty(TransactionsDetails.CompanyID, 
							TransactionsDetails.ItemCode, TransactionsDetails.UnitID, TransactionsDetails.Quantity)) AS Qty, ABS(dbo.GetItemOrgUnitQty(TransactionsDetails.CompanyID, 
							TransactionsDetails.ItemCode, TransactionsDetails.UnitID, TransactionsDetails.Bonus)) AS Bonus, 
							ABS(TransactionsDetails.Price ) AS SellValue, ABS(TransactionsDetails.DiscountPercent) AS DiscountPercent, 
							ABS(TransactionsDetails.DiscountAmount ) AS DiscountAmount, ABS(TransactionsDetails.TaxPercent) AS TaxPercent, ABS(TransactionsDetails.TaxAmount) AS TaxAmount, 
							TransactionsDetails.TaxType, Items.Name, case when TransactionsDetails.Quantity=0 then 0 else abs((TransactionsDetails.Price - TransactionsDetails.TaxAmount) /  TransactionsDetails.Quantity  )end  , 0 , 0 AS [CustomerDiscountAmount]
	FROM            TransactionsDetails INNER JOIN
							 TransactionsHeaders ON TransactionsDetails.CompanyID = TransactionsHeaders.CompanyID AND 
							 TransactionsDetails.TransactionTypeID = TransactionsHeaders.TransactionTypeID AND 
							 TransactionsDetails.TransactionYear = TransactionsHeaders.TransactionYear AND 
							 TransactionsDetails.TransactionNo = TransactionsHeaders.TransactionNo INNER JOIN
							 Items ON TransactionsDetails.CompanyID = Items.CompanyID AND TransactionsDetails.ItemCode = Items.ItemCode INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryDF ON TransactionsDetails.CompanyID = OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo AND 
							 TransactionsDetails.TransactionYear = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear AND 
							 TransactionsDetails.TransactionNo = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo AND 
							 TransactionsDetails.TransactionTypeID = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType AND 
							 TransactionsDetails.ItemCode = OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo AND TransactionsDetails.UnitID = OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode
	WHERE        (TransactionsDetails.CompanyID = @CompNo) AND (TransactionsHeaders.TransactionDate BETWEEN @RetInvDate AND @SendDate) AND 
							 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL)
							 AND (TransactionsHeaders.TransactionTypeID in (1,2)) AND (ISNULL(IsVoid,0)=0)
    
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')                     
END

else  if  @ClientActive =95
Begin

SELECT  @CashCust = Op_Value FROM  OSFA_DB.dbo.OT_SystemOptions WHERE (CompNo = @CompNo) AND (Op_ID = 226) AND (SalesmanNo=0)
-- -- - InvoiceHistory --------
	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 TransactionsHeaders INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo ON 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = TransactionsHeaders.CompanyID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType = TransactionsHeaders.TransactionTypeID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear = TransactionsHeaders.TransactionYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo = TransactionsHeaders.TransactionNo
	WHERE        (TransactionsHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (TransactionsHeaders.TransactionTypeID in (1,2))

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            TransactionsDetails INNER JOIN
							 TransactionsHeaders ON TransactionsDetails.CompanyID = TransactionsHeaders.CompanyID AND 
							 TransactionsDetails.TransactionTypeID = TransactionsHeaders.TransactionTypeID AND 
							 TransactionsDetails.TransactionYear = TransactionsHeaders.TransactionYear AND 
							 TransactionsDetails.TransactionNo = TransactionsHeaders.TransactionNo INNER JOIN
							 Items ON TransactionsDetails.CompanyID = Items.CompanyID AND TransactionsDetails.ItemCode = Items.ItemCode INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryDF ON TransactionsDetails.CompanyID = OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo AND 
							 TransactionsDetails.TransactionYear = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear AND 
							 TransactionsDetails.TransactionNo = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo AND 
							 TransactionsDetails.TransactionTypeID = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType AND 
							 TransactionsDetails.ItemCode = OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo AND TransactionsDetails.UnitID = OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode
	WHERE        (TransactionsDetails.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (TransactionsHeaders.TransactionTypeID in (1,2))
	

	INSERT INTO OSFA_DB.dbo.OT_InvoiceHistoryHF (CompNo, VouYear, VouNo, VouType, VouDate, StoreNo, SalesmanNo, CustomerNo, VouDiscPerc, CustomerDiscPerc)
	SELECT    distinct    TransactionsHeaders.CompanyID, TransactionsHeaders.TransactionYear, TransactionsHeaders.TransactionNo, TransactionsHeaders.TransactionTypeID, 
							 TransactionsHeaders.TransactionDate, 0 AS Expr1, TransactionsHeaders.SalesPersonID, TransactionsHeaders.CustomerID, 
							 ABS(TransactionsHeaders.DiscountPercent) AS DiscountPercent, ABS(TransactionsHeaders.CustomerDiscountPerc) AS CustomerDiscountPerc
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF RIGHT OUTER JOIN
							 TransactionsHeaders INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo ON 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = TransactionsHeaders.CompanyID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType = TransactionsHeaders.TransactionTypeID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear = TransactionsHeaders.TransactionYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo = TransactionsHeaders.TransactionNo
							 LEFT OUTER JOIN [dbo].[Fun_ConvArrayToTable](@CashCust,',') AS i ON TransactionsHeaders.CustomerID = i.stringPart
							 Inner Join Customers on  TransactionsHeaders.CompanyID=customers.CompanyID and 
							  TransactionsHeaders.CustomerID=Customers.ID
	WHERE        (TransactionsHeaders.CompanyID = @CompNo) AND (TransactionsHeaders.TransactionDate BETWEEN @RetInvDate AND @SendDate) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND 
							 (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL) AND (TransactionsHeaders.TransactionTypeID in (1,2)) AND (i.stringPart IS NULL) 
							 and Customers.ShortName<>1
   
    SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

    SET @BeginTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO OSFA_DB.dbo.OT_InvoiceHistoryDF
							 (CompNo, VouYear, VouNo, VouType, ItemNo, BatchNo, UnitCode, Qty, Bonus, SellValue, DiscPerc, DiscValue, TaxPerc, TaxValue, TaxType, ItemDesc,UnitPrice)
	SELECT     distinct   TransactionsDetails.CompanyID, TransactionsDetails.TransactionYear, TransactionsDetails.TransactionNo, TransactionsDetails.TransactionTypeID, 
							 TransactionsDetails.ItemCode, '0' AS BatchNo, TransactionsDetails.UnitID, ABS(dbo.GetItemOrgUnitQty(TransactionsDetails.CompanyID, 
						  TransactionsDetails.ItemCode, TransactionsDetails.UnitID, TransactionsDetails.Quantity)) AS Qty, ABS(dbo.GetItemOrgUnitQty(TransactionsDetails.CompanyID, 
						  TransactionsDetails.ItemCode, TransactionsDetails.UnitID, TransactionsDetails.Bonus)) AS Bonus, 
							 ABS(TransactionsDetails.Price ) AS SellValue, ABS(TransactionsDetails.DiscountPercent) AS DiscountPercent, 
							 ABS(TransactionsDetails.DiscountAmount) AS DiscountAmount, ABS(TransactionsDetails.TaxPercent) AS TaxPercent, ABS(TransactionsDetails.TaxAmount) AS TaxAmount, 
							 TransactionsDetails.TaxType, Items.Name, abs(TransactionsDetails.UPrice)
	FROM            TransactionsDetails INNER JOIN
							 TransactionsHeaders ON TransactionsDetails.CompanyID = TransactionsHeaders.CompanyID AND 
							 TransactionsDetails.TransactionTypeID = TransactionsHeaders.TransactionTypeID AND 
							 TransactionsDetails.TransactionYear = TransactionsHeaders.TransactionYear AND 
							 TransactionsDetails.TransactionNo = TransactionsHeaders.TransactionNo INNER JOIN
							 Items ON TransactionsDetails.CompanyID = Items.CompanyID AND TransactionsDetails.ItemCode = Items.ItemCode INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryDF ON TransactionsDetails.CompanyID = OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo AND 
							 TransactionsDetails.TransactionYear = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear AND 
							 TransactionsDetails.TransactionNo = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo AND 
							 TransactionsDetails.TransactionTypeID = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType AND 
							 TransactionsDetails.ItemCode = OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo AND TransactionsDetails.UnitID =
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode
							 LEFT OUTER JOIN [dbo].[Fun_ConvArrayToTable](@CashCust,',') AS i ON TransactionsHeaders.CustomerID = i.stringPart  
							 Inner Join Customers on  TransactionsHeaders.CompanyID=customers.CompanyID and 
							  TransactionsHeaders.CustomerID=Customers.ID
	WHERE        (TransactionsDetails.CompanyID = @CompNo) AND (TransactionsHeaders.TransactionDate BETWEEN @RetInvDate AND @SendDate) AND 
							 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL)
							 AND (TransactionsHeaders.TransactionTypeID in (1,2)) AND (i.stringPart IS NULL)  and Customers.ShortName<>1
    
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')                     
END



else if @ClientActive=88
Begin
SET @RetInvDate = DATEADD(M,-1, @SendDate)
end


else  if @ClientActive in (136,41)
BEGIN
select 0
END

else if @ClientActive =78
Begin

select 'OT_InvoiceHistoryHF'
-- -- - InvoiceHistory --------
	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 TransactionsHeaders INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo ON 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = TransactionsHeaders.CompanyID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType = TransactionsHeaders.TransactionTypeID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear = TransactionsHeaders.TransactionYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo = TransactionsHeaders.TransactionNo
	WHERE        (TransactionsHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
				AND (TransactionsHeaders.TransactionTypeID in (1,2))

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            TransactionsDetails INNER JOIN
							 TransactionsHeaders ON TransactionsDetails.CompanyID = TransactionsHeaders.CompanyID AND 
							 TransactionsDetails.TransactionTypeID = TransactionsHeaders.TransactionTypeID AND 
							 TransactionsDetails.TransactionYear = TransactionsHeaders.TransactionYear AND 
							 TransactionsDetails.TransactionNo = TransactionsHeaders.TransactionNo INNER JOIN
							 Items ON TransactionsDetails.CompanyID = Items.CompanyID AND TransactionsDetails.ItemCode = Items.ItemCode INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryDF ON TransactionsDetails.CompanyID = OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo AND 
							 TransactionsDetails.TransactionYear = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear AND 
							 TransactionsDetails.TransactionNo = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo AND 
							 TransactionsDetails.TransactionTypeID = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType AND 
							 TransactionsDetails.ItemCode = OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo AND TransactionsDetails.UnitID = OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode
	WHERE        (TransactionsDetails.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (TransactionsHeaders.TransactionTypeID in (1,2))

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO OSFA_DB.dbo.OT_InvoiceHistoryHF (CompNo, VouYear, VouNo, VouType, VouDate, StoreNo, SalesmanNo, CustomerNo, VouDiscPerc, CustomerDiscPerc)
	SELECT    distinct    TransactionsHeaders.CompanyID, TransactionsHeaders.TransactionYear, TransactionsHeaders.TransactionNo, TransactionsHeaders.TransactionTypeID, 
							 TransactionsHeaders.TransactionDate, 0 AS Expr1, TransactionsHeaders.SalesPersonID, TransactionsHeaders.CustomerID, 
							 ABS(TransactionsHeaders.DiscountPercent) AS DiscountPercent, ABS(TransactionsHeaders.CustomerDiscountPerc) AS CustomerDiscountPerc
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF RIGHT OUTER JOIN
							 TransactionsHeaders INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo ON 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = TransactionsHeaders.CompanyID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType = TransactionsHeaders.TransactionTypeID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear = TransactionsHeaders.TransactionYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo = TransactionsHeaders.TransactionNo
	WHERE        (TransactionsHeaders.CompanyID = @CompNo) AND (TransactionsHeaders.TransactionDate BETWEEN @RetInvDate AND @SendDate) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND 
							 (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL) AND (TransactionsHeaders.TransactionTypeID in (1,2)) AND (ISNULL(IsVoid,0)=0)
							 and TransactionsHeaders.SalesPersonID=@SalesmanNo
   
    SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

    SET @BeginTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO OSFA_DB.dbo.OT_InvoiceHistoryDF
							 (CompNo, VouYear, VouNo, VouType, ItemNo, BatchNo, UnitCode, Qty, Bonus, SellValue, DiscPerc, DiscValue, TaxPerc, TaxValue, TaxType, ItemDesc,UnitPrice,VouDiscValue,CustDiscValue)
	SELECT     distinct   TransactionsDetails.CompanyID, TransactionsDetails.TransactionYear, TransactionsDetails.TransactionNo, TransactionsDetails.TransactionTypeID, 
							TransactionsDetails.ItemCode, '0' AS BatchNo, TransactionsDetails.UnitID, ABS(dbo.GetItemOrgUnitQty(TransactionsDetails.CompanyID, 
							TransactionsDetails.ItemCode, TransactionsDetails.UnitID, TransactionsDetails.Quantity)) AS Qty, ABS(dbo.GetItemOrgUnitQty(TransactionsDetails.CompanyID, 
							TransactionsDetails.ItemCode, TransactionsDetails.UnitID, TransactionsDetails.Bonus)) AS Bonus, 
							ABS(TransactionsDetails.Price ) AS SellValue, ABS(TransactionsDetails.DiscountPercent) AS DiscountPercent, 
							ABS(TransactionsDetails.DiscountAmount ) AS DiscountAmount, ABS(TransactionsDetails.TaxPercent) AS TaxPercent, ABS(TransactionsDetails.TaxAmount) AS TaxAmount, 
							TransactionsDetails.TaxType, Items.Name, abs(TransactionsDetails.UPrice), abs(TransactionsDetails.[VoucherDiscount]), abs(TransactionsDetails.[CustomerDiscountAmount]) AS [CustomerDiscountAmount]
	FROM            TransactionsDetails INNER JOIN
							 TransactionsHeaders ON TransactionsDetails.CompanyID = TransactionsHeaders.CompanyID AND 
							 TransactionsDetails.TransactionTypeID = TransactionsHeaders.TransactionTypeID AND 
							 TransactionsDetails.TransactionYear = TransactionsHeaders.TransactionYear AND 
							 TransactionsDetails.TransactionNo = TransactionsHeaders.TransactionNo INNER JOIN
							 Items ON TransactionsDetails.CompanyID = Items.CompanyID AND TransactionsDetails.ItemCode = Items.ItemCode INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryDF ON TransactionsDetails.CompanyID = OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo AND 
							 TransactionsDetails.TransactionYear = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear AND 
							 TransactionsDetails.TransactionNo = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo AND 
							 TransactionsDetails.TransactionTypeID = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType AND 
							 TransactionsDetails.ItemCode = OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo AND TransactionsDetails.UnitID = OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode
	WHERE        (TransactionsDetails.CompanyID = @CompNo) AND (TransactionsHeaders.TransactionDate BETWEEN @RetInvDate AND @SendDate) AND 
							 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL)
							 AND (TransactionsHeaders.TransactionTypeID in (1,2)) AND (ISNULL(IsVoid,0)=0)
    
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')                     
END


else if @ClientActive =85 AND @SalesmanGroupID=4
Begin  

	SET @BeginTime = Convert(varchar(20),GetDate(),108)
-- -- - InvoiceHistory --------
	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 TransactionsHeaders INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo ON 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = TransactionsHeaders.CompanyID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType = TransactionsHeaders.TransactionTypeID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear = TransactionsHeaders.TransactionYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo = TransactionsHeaders.TransactionNo
	WHERE        (TransactionsHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
				AND (TransactionsHeaders.TransactionTypeID in (1,2))

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            TransactionsDetails INNER JOIN
							 TransactionsHeaders ON TransactionsDetails.CompanyID = TransactionsHeaders.CompanyID AND 
							 TransactionsDetails.TransactionTypeID = TransactionsHeaders.TransactionTypeID AND 
							 TransactionsDetails.TransactionYear = TransactionsHeaders.TransactionYear AND 
							 TransactionsDetails.TransactionNo = TransactionsHeaders.TransactionNo INNER JOIN
							 Items ON TransactionsDetails.CompanyID = Items.CompanyID AND TransactionsDetails.ItemCode = Items.ItemCode INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryDF ON TransactionsDetails.CompanyID = OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo AND 
							 TransactionsDetails.TransactionYear = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear AND 
							 TransactionsDetails.TransactionNo = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo AND 
							 TransactionsDetails.TransactionTypeID = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType AND 
							 TransactionsDetails.ItemCode = OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo AND TransactionsDetails.UnitID = OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode
	WHERE        (TransactionsDetails.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (TransactionsHeaders.TransactionTypeID in (1,2))
	
	INSERT INTO OSFA_DB.dbo.OT_InvoiceHistoryHF (CompNo, VouYear, VouNo, VouType, VouDate, StoreNo, SalesmanNo, CustomerNo, VouDiscPerc, CustomerDiscPerc)
	SELECT    distinct    TransactionsHeaders.CompanyID, TransactionsHeaders.TransactionYear, TransactionsHeaders.TransactionNo, TransactionsHeaders.TransactionTypeID, 
							 TransactionsHeaders.TransactionDate, 0 AS Expr1, TransactionsHeaders.SalesPersonID, TransactionsHeaders.CustomerID, 
							 ABS(TransactionsHeaders.DiscountPercent) AS DiscountPercent, ABS(TransactionsHeaders.CustomerDiscountPerc) AS CustomerDiscountPerc
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF RIGHT OUTER JOIN
							 TransactionsHeaders INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo ON 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = TransactionsHeaders.CompanyID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType = TransactionsHeaders.TransactionTypeID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear = TransactionsHeaders.TransactionYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo = TransactionsHeaders.TransactionNo
	WHERE        (TransactionsHeaders.CompanyID = @CompNo) AND (TransactionsHeaders.TransactionDate BETWEEN @RetInvDate AND @SendDate) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND 
							 (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL) AND (TransactionsHeaders.TransactionTypeID in (1,2)) AND (ISNULL(IsVoid,0)=0)
   
    SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

    SET @BeginTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO OSFA_DB.dbo.OT_InvoiceHistoryDF
							 (CompNo, VouYear, VouNo, VouType, ItemNo, BatchNo, UnitCode, Qty, Bonus, SellValue, DiscPerc, DiscValue, TaxPerc, TaxValue, TaxType, ItemDesc,UnitPrice,VouDiscValue,CustDiscValue)
	SELECT     distinct   TransactionsDetails.CompanyID, TransactionsDetails.TransactionYear, TransactionsDetails.TransactionNo, TransactionsDetails.TransactionTypeID, 
							TransactionsDetails.ItemCode, '0' AS BatchNo, TransactionsDetails.UnitID, ABS(dbo.GetItemOrgUnitQty(TransactionsDetails.CompanyID, 
							TransactionsDetails.ItemCode, TransactionsDetails.UnitID, TransactionsDetails.Quantity)) AS Qty, ABS(dbo.GetItemOrgUnitQty(TransactionsDetails.CompanyID, 
							TransactionsDetails.ItemCode, TransactionsDetails.UnitID, TransactionsDetails.Bonus)) AS Bonus, 
							ABS(TransactionsDetails.Price ) AS SellValue, ABS(TransactionsDetails.DiscountPercent) AS DiscountPercent, 
							ABS(TransactionsDetails.DiscountAmount ) AS DiscountAmount, ABS(TransactionsDetails.TaxPercent) AS TaxPercent, ABS(TransactionsDetails.TaxAmount) AS TaxAmount, 
							TransactionsDetails.TaxType, Items.Name, abs(TransactionsDetails.UPrice), abs(TransactionsDetails.[VoucherDiscount]), abs(TransactionsDetails.[CustomerDiscountAmount]) AS [CustomerDiscountAmount]
	FROM            TransactionsDetails INNER JOIN
							 TransactionsHeaders ON TransactionsDetails.CompanyID = TransactionsHeaders.CompanyID AND 
							 TransactionsDetails.TransactionTypeID = TransactionsHeaders.TransactionTypeID AND 
							 TransactionsDetails.TransactionYear = TransactionsHeaders.TransactionYear AND 
							 TransactionsDetails.TransactionNo = TransactionsHeaders.TransactionNo INNER JOIN
							 Items ON TransactionsDetails.CompanyID = Items.CompanyID AND TransactionsDetails.ItemCode = Items.ItemCode INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryDF ON TransactionsDetails.CompanyID = OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo AND 
							 TransactionsDetails.TransactionYear = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear AND 
							 TransactionsDetails.TransactionNo = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo AND 
							 TransactionsDetails.TransactionTypeID = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType AND 
							 TransactionsDetails.ItemCode = OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo AND TransactionsDetails.UnitID = OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode
	WHERE        (TransactionsDetails.CompanyID = @CompNo) AND (TransactionsHeaders.TransactionDate BETWEEN @RetInvDate AND @SendDate) AND 
							 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL)
							 AND (TransactionsHeaders.TransactionTypeID in (1,2)) AND (ISNULL(IsVoid,0)=0)
    
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')                     
END

else
Begin
print 'OSAMA'
	SET @BeginTime = Convert(varchar(20),GetDate(),108)
-- -- - InvoiceHistory --------
	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 TransactionsHeaders INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo ON 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = TransactionsHeaders.CompanyID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType = TransactionsHeaders.TransactionTypeID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear = TransactionsHeaders.TransactionYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo = TransactionsHeaders.TransactionNo
	WHERE        (TransactionsHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
				AND (TransactionsHeaders.TransactionTypeID in (1,2))

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            TransactionsDetails INNER JOIN
							 TransactionsHeaders ON TransactionsDetails.CompanyID = TransactionsHeaders.CompanyID AND 
							 TransactionsDetails.TransactionTypeID = TransactionsHeaders.TransactionTypeID AND 
							 TransactionsDetails.TransactionYear = TransactionsHeaders.TransactionYear AND 
							 TransactionsDetails.TransactionNo = TransactionsHeaders.TransactionNo INNER JOIN
							 Items ON TransactionsDetails.CompanyID = Items.CompanyID AND TransactionsDetails.ItemCode = Items.ItemCode INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryDF ON TransactionsDetails.CompanyID = OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo AND 
							 TransactionsDetails.TransactionYear = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear AND 
							 TransactionsDetails.TransactionNo = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo AND 
							 TransactionsDetails.TransactionTypeID = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType AND 
							 TransactionsDetails.ItemCode = OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo AND TransactionsDetails.UnitID = OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode
	WHERE        (TransactionsDetails.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (TransactionsHeaders.TransactionTypeID in (1,2))
	
	INSERT INTO OSFA_DB.dbo.OT_InvoiceHistoryHF (CompNo, VouYear, VouNo, VouType, VouDate, StoreNo, SalesmanNo, CustomerNo, VouDiscPerc, CustomerDiscPerc,PaymentDiscPerc,PaymentDiscAmt)
	SELECT    distinct    TransactionsHeaders.CompanyID, TransactionsHeaders.TransactionYear, TransactionsHeaders.TransactionNo, TransactionsHeaders.TransactionTypeID, 
							 TransactionsHeaders.TransactionDate, 0 AS Expr1, TransactionsHeaders.SalesPersonID, TransactionsHeaders.CustomerID, 
							 ABS(TransactionsHeaders.DiscountPercent) AS DiscountPercent, ABS(TransactionsHeaders.CustomerDiscountPerc) AS CustomerDiscountPerc,0,0
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF RIGHT OUTER JOIN
							 TransactionsHeaders INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo ON 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = TransactionsHeaders.CompanyID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType = TransactionsHeaders.TransactionTypeID AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear = TransactionsHeaders.TransactionYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo = TransactionsHeaders.TransactionNo
	WHERE        (TransactionsHeaders.CompanyID = @CompNo) AND (TransactionsHeaders.TransactionDate BETWEEN @RetInvDate AND @SendDate) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND 
							 (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL) AND (TransactionsHeaders.TransactionTypeID in (1,2)) AND (ISNULL(IsVoid,0)=0)
   
    SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

    SET @BeginTime = Convert(varchar(20),GetDate(),108)

	INSERT INTO OSFA_DB.dbo.OT_InvoiceHistoryDF
							 (CompNo, VouYear, VouNo, VouType, ItemNo, BatchNo, UnitCode, Qty, Bonus, SellValue, DiscPerc, DiscValue, TaxPerc, TaxValue, TaxType, ItemDesc,UnitPrice,VouDiscValue,CustDiscValue)
	SELECT     distinct   TransactionsDetails.CompanyID, TransactionsDetails.TransactionYear, TransactionsDetails.TransactionNo, TransactionsDetails.TransactionTypeID, 
							TransactionsDetails.ItemCode, '0' AS BatchNo, TransactionsDetails.UnitID, ABS(dbo.GetItemOrgUnitQty(TransactionsDetails.CompanyID, 
							TransactionsDetails.ItemCode, TransactionsDetails.UnitID, TransactionsDetails.Quantity)) AS Qty, ABS(dbo.GetItemOrgUnitQty(TransactionsDetails.CompanyID, 
							TransactionsDetails.ItemCode, TransactionsDetails.UnitID, TransactionsDetails.Bonus)) AS Bonus, 
							ABS(TransactionsDetails.Price ) AS SellValue, ABS(TransactionsDetails.DiscountPercent) AS DiscountPercent, 
							ABS(TransactionsDetails.DiscountAmount ) AS DiscountAmount, ABS(TransactionsDetails.TaxPercent) AS TaxPercent, ABS(TransactionsDetails.TaxAmount) AS TaxAmount, 
							TransactionsDetails.TaxType, Items.Name, abs(TransactionsDetails.UPrice), abs(TransactionsDetails.[VoucherDiscount]), abs(TransactionsDetails.[CustomerDiscountAmount]) AS [CustomerDiscountAmount]
	FROM            TransactionsDetails INNER JOIN
							 TransactionsHeaders ON TransactionsDetails.CompanyID = TransactionsHeaders.CompanyID AND 
							 TransactionsDetails.TransactionTypeID = TransactionsHeaders.TransactionTypeID AND 
							 TransactionsDetails.TransactionYear = TransactionsHeaders.TransactionYear AND 
							 TransactionsDetails.TransactionNo = TransactionsHeaders.TransactionNo INNER JOIN
							 Items ON TransactionsDetails.CompanyID = Items.CompanyID AND TransactionsDetails.ItemCode = Items.ItemCode INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON TransactionsHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 TransactionsHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryDF ON TransactionsDetails.CompanyID = OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo AND 
							 TransactionsDetails.TransactionYear = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear AND 
							 TransactionsDetails.TransactionNo = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo AND 
							 TransactionsDetails.TransactionTypeID = OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType AND 
							 TransactionsDetails.ItemCode = OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo AND TransactionsDetails.UnitID = OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode
	WHERE        (TransactionsDetails.CompanyID = @CompNo) AND (TransactionsHeaders.TransactionDate BETWEEN @RetInvDate AND @SendDate) AND 
							 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL)
							 AND (TransactionsHeaders.TransactionTypeID in (1,2)) AND (ISNULL(IsVoid,0)=0)
    
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')                     
END

END
else if @ClientActive=153

Begin 

	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryDF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF INNER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)


	DELETE FROM OSFA_DB.dbo.OT_InvoiceHistoryHF
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
	WHERE        (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryHF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[VouDate]
			   ,[StoreNo]
			   ,[SalesmanNo]
			   ,[CustomerNo])
	SELECT        InvoiceHistoryHF.CompNo, InvoiceHistoryHF.VouYear, InvoiceHistoryHF.VouNo, InvoiceHistoryHF.VouType, InvoiceHistoryHF.VouDate, InvoiceHistoryHF.StoreNo, 
							 InvoiceHistoryHF.SalesmanNo, InvoiceHistoryHF.CustomerNo
	FROM            InvoiceHistoryHF INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo LEFT OUTER JOIN
							 OSFA_DB.dbo.OT_InvoiceHistoryHF ON InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo AND 
							 InvoiceHistoryHF.VouYear = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouYear AND InvoiceHistoryHF.VouNo = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouNo AND 
							 InvoiceHistoryHF.VouType = OSFA_DB.dbo.OT_InvoiceHistoryHF.VouType
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryHF.CompNo IS NULL) AND 
							 (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
							 order by InvoiceHistoryHF.VouDate
	
	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceHistoryHF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

    SET @BeginTime = Convert(varchar(20),GetDate(),108) 
	             
	INSERT INTO [OSFA_DB].[dbo].[OT_InvoiceHistoryDF]
			   ([CompNo]
			   ,[VouYear]
			   ,[VouNo]
			   ,[VouType]
			   ,[ItemNo]
			   ,[BatchNo]
			   ,[UnitCode]
			   ,[Qty]
			   ,[Bonus]
			   ,[SellValue]
			   ,[DiscPerc]
			   ,[DiscValue]
			   ,[TaxPerc]
			   ,[TaxValue]
			   ,[ItemDesc],TaxType)
	SELECT        InvoiceHistoryDF.CompNo, InvoiceHistoryDF.VouYear, InvoiceHistoryDF.VouNo, InvoiceHistoryDF.VouType, InvoiceHistoryDF.ItemNo, InvoiceHistoryDF.BatchNo, 
							 InvoiceHistoryDF.UnitCode, InvoiceHistoryDF.Qty, InvoiceHistoryDF.Bonus, InvoiceHistoryDF.SellValue *1500, InvoiceHistoryDF.DiscPerc, InvoiceHistoryDF.DiscValue, 
							 InvoiceHistoryDF.TaxPerc, InvoiceHistoryDF.TaxValue , InvoiceHistoryDF.ItemDesc,1
	FROM            OSFA_DB.dbo.OT_InvoiceHistoryDF RIGHT OUTER JOIN
							 InvoiceHistoryHF INNER JOIN
							 InvoiceHistoryDF ON InvoiceHistoryHF.CompNo = InvoiceHistoryDF.CompNo AND InvoiceHistoryHF.VouYear = InvoiceHistoryDF.VouYear AND 
							 InvoiceHistoryHF.VouNo = InvoiceHistoryDF.VouNo AND InvoiceHistoryHF.VouType = InvoiceHistoryDF.VouType INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON InvoiceHistoryHF.CustomerNo = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND 
							 InvoiceHistoryHF.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo ON OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo = InvoiceHistoryDF.CompNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouYear = InvoiceHistoryDF.VouYear AND OSFA_DB.dbo.OT_InvoiceHistoryDF.VouNo = InvoiceHistoryDF.VouNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.VouType = InvoiceHistoryDF.VouType AND OSFA_DB.dbo.OT_InvoiceHistoryDF.ItemNo = InvoiceHistoryDF.ItemNo AND 
							 OSFA_DB.dbo.OT_InvoiceHistoryDF.BatchNo = InvoiceHistoryDF.BatchNo AND OSFA_DB.dbo.OT_InvoiceHistoryDF.UnitCode = InvoiceHistoryDF.UnitCode
	WHERE        (InvoiceHistoryHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHistoryDF.CompNo IS NULL) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)   
    order by InvoiceHistoryHF.VouDate

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'InvoiceHistoryDF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

END 


SET @BeginTime = Convert(varchar(20),GetDate(),108)

INSERT INTO OSFA_DB.dbo.OT_InvoiceReturnLinkToTab (CompNo, SalesmanNo, RetVouType, RetVouYear, RetVouNo, InvVouType, InvVouYear, InvVouNo, ItemCode, UnitID, Qty, Bonus, UnitPrice)
SELECT    DISTINCT    InvoiceReturnLink.CompanyID, OSFA_DB.dbo.OT_CustomerMF.SalesmanNo, InvoiceReturnLink.RetVouType, InvoiceReturnLink.RetVouYear, 
                         InvoiceReturnLink.RetVouNo, InvoiceReturnLink.InvVouType, InvoiceReturnLink.InvVouYear, InvoiceReturnLink.InvVouNo, InvoiceReturnLink.ItemCode, 
                         InvoiceReturnLink.UnitID, InvoiceReturnLink.Qty, InvoiceReturnLink.Bonus, InvoiceReturnLink.UnitPrice
FROM            OSFA_DB.dbo.OT_CustomerMF INNER JOIN
                         InvoiceReturnLink INNER JOIN
                         OSFA_DB.dbo.OT_InvoiceHistoryHF ON InvoiceReturnLink.InvVouType = OT_InvoiceHistoryHF.VouType AND InvoiceReturnLink.InvVouNo = OT_InvoiceHistoryHF.VouNo AND 
                         InvoiceReturnLink.InvVouYear = OT_InvoiceHistoryHF.VouYear AND InvoiceReturnLink.CompanyID = OT_InvoiceHistoryHF.CompNo ON 
                         OSFA_DB.dbo.OT_CustomerMF.CompNo = OT_InvoiceHistoryHF.CompNo AND OSFA_DB.dbo.OT_CustomerMF.CustomerNo = OT_InvoiceHistoryHF.CustomerNo
WHERE        (InvoiceReturnLink.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

							 
-- Competitive Items ------------------------------------------------------------
INSERT INTO OSFA_DB.dbo.OT_CompetitiveItems (CompanyID, SalesmanNo, CompetitiveItemCode, ItemCode, Name, CategCode, CompetitiveCompany, ImageID)
SELECT        CompetitiveItems.CompanyID, @SalesmanNo, CompetitiveItems.CompetitiveItemCode, CompetitiveItems.ItemCode, CompetitiveItems.Name, 
                         CompetitiveItems.CategCode, CompetitiveItems.CompetitiveCompany, row_number() over (Order by CompetitiveItemCode) AS img
FROM            SalesPersonItemsAssignment INNER JOIN
                         CompetitiveItems ON SalesPersonItemsAssignment.CompanyID = CompetitiveItems.CompanyID AND 
                         SalesPersonItemsAssignment.ItemCode = CompetitiveItems.ItemCode
WHERE        (SalesPersonItemsAssignment.PositionsID = @PositionsID) AND (CompetitiveItems.CompanyID = @CompNo)

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_InvoiceReturnLinkToTab, OT_CompetitiveItems [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']') 

-- --------------------------------------------------------------------------------

SET @BeginTime = Convert(varchar(20),GetDate(),108)

IF @ClientActive = 8 -- Saftey Food
BEGIN
	INSERT INTO OSFA_DB.dbo.OT_CustomerChqList(CompNo, SalesmanNo, CustomerID, ChqNo, DeptNo, DeptName, BankNo, BankDesc, DueDate, VouNo, VouDate, ChqStatus, Amount, PaidAmount, RemAmount)
	SELECT        CustomerChqList.CompNo, Alpha_Integration.dbo.SalesmanDeptLink.SalesmanNo, CustomerChqList.CustomerID, CustomerChqList.ChqNo, 
							 CustomerChqList.DeptNo, CustomerChqList.DeptName, CustomerChqList.BankNo, CustomerChqList.BankDesc, CustomerChqList.DueDate, CustomerChqList.VouNo, 
							 CustomerChqList.VouDate, CustomerChqList.ChqStatus, CustomerChqList.Amount, CustomerChqList.PaidAmount, CustomerChqList.RemAmount
	FROM            CustomerChqList INNER JOIN
							 Alpha_Integration.dbo.SalesmanDeptLink ON CustomerChqList.CompNo = Alpha_Integration.dbo.SalesmanDeptLink.CompNo AND 
							 CustomerChqList.DeptNo = Alpha_Integration.dbo.SalesmanDeptLink.DeptNo
	WHERE        (CustomerChqList.CompNo = @CompNo) AND (CustomerChqList.CustomerID IN
								 (SELECT        CustomerNo
									FROM            OSFA_DB.dbo.OT_CustomerMF
									WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo))) AND (Alpha_Integration.dbo.SalesmanDeptLink.SalesmanNo = @SalesmanNo)
END
ELSE
BEGIN
	INSERT INTO OSFA_DB.dbo.OT_CustomerChqList(CompNo, SalesmanNo, CustomerID, ChqNo, DeptNo, DeptName, BankNo, BankDesc, DueDate, VouNo, VouDate, ChqStatus, Amount, PaidAmount, RemAmount)
	SELECT        CompNo, @SalesmanNo, CustomerID, ChqNo, DeptNo, DeptName, BankNo, BankDesc, DueDate, VouNo, VouDate, ChqStatus, Amount, PaidAmount, RemAmount
	FROM            CustomerChqList
	WHERE        (CompNo = @CompNo) AND CustomerID IN(SELECT [CustomerNo] FROM [OSFA_DB].[dbo].[OT_CustomerMF] 
													   WHERE (CompNo=@CompNo) AND (SalesmanNo = @SalesmanNo))
END


-----------------------------------------------------------------------------------

/*
---------------------------------
	DECLARE @cCompItemNo varchar(100)
	DECLARE @xi bigint
	SET @xi = 1
	
	DECLARE xItems CURSOR FOR

		SELECT        CompetitiveItemCode
		FROM            OSFA_DB.dbo.OT_CompetitiveItems
		WHERE        (CompanyID = @CompNo) AND (SalesmanNo = @SalesmanNo)

	OPEN xItems
		FETCH NEXT FROM xItems
		INTO @cCompItemNo
			WHILE @@FETCH_STATUS = 0
			BEGIN
			 
				UPDATE [OSFA_DB].[dbo].[OT_CompetitiveItems] SET ImageID = @xi
				WHERE (CompanyID = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (CompetitiveItemCode = @cCompItemNo)
			
				SET @xi = @xi + 1
				
				FETCH NEXT FROM xItems
				INTO @cCompItemNo
			END
	CLOSE xItems
	DEALLOCATE xItems 
---------------------------------
*/

--///////////////////// CustomerSalesByCategory /////////////////////////////////////////
INSERT INTO OSFA_DB.dbo.OT_CustomerSalesByCategory
                         (CompNo, SalesmanNo, CustomerNo, Categ, NetSales)
SELECT        CompNo, CustomerNo, @SalesmanNo, Categ, NetSales
FROM           CustomerSalesByCategory
WHERE     (CompNo = @CompNo) AND (CustomerNo IN
                          (SELECT     CustomerNo
                             FROM         OSFA_DB.dbo.OT_CustomerMF
                             WHERE     (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)))


SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_CustomerChqList, OT_CustomerSalesByCategory [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']') 

---//////////////// Serials By Book /////////////////////////////////
	Declare @MaxInvNo int
	Declare @MaxRetInvNo int
	Declare @MaxRecNo int
	declare @D smalldatetime
	declare @InvFromNo int
	declare @InvToNo int
	declare @RetFromNo int
	declare @RetToNo int
	declare @RecFromNo int
	declare @RecToNo int

IF @SerialType = 1 
BEGIN
	
	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	--/////// Invoice ///////////////////////////////
	SELECT   Top (1) @MaxInvNo = MAX(VouNo), @D = VouDate                        
	FROM            OSFA_DB.dbo.OT_InvoiceHF
	WHERE        (CompNo = @CompNo) AND (VouType = 1) AND (VouYear = Year(@SendDate)) AND (SalesmanNo = @SalesmanNo)
	Group By VouDate
	ORDER BY VouDate Desc

	if NOT(@MaxInvNo IS NULL)
	BEGIN
		SELECT        @InvFromNo = FromNo, @InvToNo = ToNo
		FROM            SalesPersonNotbookTransactionsSerials
		WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (SerYear = Year(@SendDate)) AND (NextSerial <= ToNo) AND (@MaxInvNo BETWEEN FromNo AND ToNo) AND (SerType = 1)
		IF @@Rowcount <> 0
		BEGIN
			SELECT @MaxInvNo = Max(VouNo) 
			FROM OSFA_DB.dbo.OT_InvoiceHF 
			WHERE (CompNo = @CompNo) AND (VouType = 1) AND (VouYear = Year(@SendDate)) AND (VouNo between @InvFromNo and @InvToNo)
		END

		UPDATE       SalesPersonNotbookTransactionsSerials
		SET                NextSerial = @MaxInvNo + 1
		WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (SerYear = YEAR(@SendDate)) AND (NextSerial <= ToNo) AND (@MaxInvNo BETWEEN FromNo AND ToNo) AND (SerType = 1) and isnull(IsSuspended,0) = 0
		if @@Rowcount <> 0
		begin
			UPDATE       SalesPersonNotbookTransactionsSerials
			SET                IsSuspended = 1
			WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (SerYear = YEAR(@SendDate)) AND (NextSerial <= ToNo) AND NOT(@MaxInvNo BETWEEN FromNo AND ToNo) AND (SerType = 1) AND (ToNo < @MaxInvNo)
		end
		
	END
	--/////// Return Invoice ///////////////////////
	SELECT     Top (1)   @MaxRetInvNo = MAX(VouNo), @D = VouDate                       
	FROM            OSFA_DB.dbo.OT_InvoiceHF
	WHERE        (CompNo = @CompNo) AND (VouType = 2) AND (VouYear = Year(@SendDate)) AND (SalesmanNo = @SalesmanNo)
	Group By VouDate
	ORDER BY VouDate Desc

	if NOT(@MaxRetInvNo IS NULL)
	BEGIN	
		SELECT        @RetFromNo = FromNo, @RetToNo = ToNo
		FROM            SalesPersonNotbookTransactionsSerials
		WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (SerYear = Year(@SendDate)) AND (NextSerial <= ToNo) AND (@MaxRetInvNo BETWEEN FromNo AND ToNo) AND (SerType = 2)
		IF @@Rowcount <> 0
		BEGIN
			SELECT @MaxRetInvNo = Max(VouNo) 
			FROM OSFA_DB.dbo.OT_InvoiceHF 
			WHERE (CompNo = @CompNo) AND (VouType = 2) AND (VouYear = Year(@SendDate)) AND (VouNo between @RetFromNo and @RetToNo)
		END

		UPDATE       SalesPersonNotbookTransactionsSerials
		SET                NextSerial = @MaxRetInvNo + 1
		WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (SerYear = YEAR(@SendDate)) AND (NextSerial <= ToNo) AND (@MaxRetInvNo BETWEEN FromNo AND ToNo) AND (SerType = 2) and isnull(IsSuspended,0) = 0
		if @@Rowcount <> 0
		begin
			UPDATE       SalesPersonNotbookTransactionsSerials
			SET                IsSuspended = 1
			WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (SerYear = YEAR(@SendDate)) AND (NextSerial <= ToNo) AND NOT(@MaxRetInvNo BETWEEN FromNo AND ToNo) AND (SerType = 2) AND (ToNo < @MaxRetInvNo)
		end
	END
	--/////// Receipt //////////////////////////////
	SELECT      Top (1)   @MaxRecNo = MAX(VouNo) , @D = VouDate                           
	FROM            OSFA_DB.dbo.OT_Payments
	WHERE        (CompNo = @CompNo) AND (VouType = 3) AND (VouYear = Year(@SendDate)) AND (SalesmanNo = @SalesmanNo)
	Group By VouDate
	ORDER BY VouDate Desc

	if NOT(@MaxRecNo IS NULL)
	BEGIN		
		SELECT        @RecFromNo = FromNo, @RecToNo = ToNo
		FROM            SalesPersonNotbookTransactionsSerials
		WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (SerYear = Year(@SendDate)) AND (NextSerial <= ToNo) AND (@MaxRecNo BETWEEN FromNo AND ToNo) AND (SerType = 3)
		IF @@Rowcount <> 0
		BEGIN
			SELECT @MaxRecNo = Max(VouNo) 
			FROM OSFA_DB.dbo.OT_Payments 
			WHERE (CompNo = @CompNo) AND (VouType = 3) AND (VouYear = Year(@SendDate)) AND (VouNo between @RecFromNo and @RecToNo)
		END

		UPDATE       SalesPersonNotbookTransactionsSerials
		SET                NextSerial = @MaxRecNo + 1
		WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (SerYear = YEAR(@SendDate)) AND (NextSerial <= ToNo) AND (@MaxRecNo BETWEEN FromNo AND ToNo) AND (SerType = 3) and isnull(IsSuspended,0) = 0
		if @@Rowcount <> 0
		begin
			UPDATE       SalesPersonNotbookTransactionsSerials
			SET                IsSuspended = 1
			WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (SerYear = YEAR(@SendDate)) AND (NextSerial <= ToNo) AND NOT(@MaxRecNo BETWEEN FromNo AND ToNo) AND (SerType = 3) AND (ToNo < @MaxRecNo)
		end
	END
	--///
	INSERT INTO [OSFA_DB].[dbo].[OT_SalesmanNotebookSerials]
           ([CompNo]
           ,[SalesmanNo]
           ,[SerYear]
           ,[SerType]
           ,[NotebookNo]
           ,[FromNo]
           ,[ToNo]
           ,[NextSerial]
		   ,[CustomerNo])
	SELECT        CompanyID, SalesPersonID, SerYear, SerType, NotbookNo, FromNo, ToNo, NextSerial, CustomerID
	FROM            SalesPersonNotbookTransactionsSerials
	WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (SerYear = Year(@SendDate)) AND (NextSerial <= ToNo) AND (IsNull(IsSuspended,0) = 0)
	ORDER BY NotbookNo

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_SalesmanNotebookSerials - Serial By Notebook [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
END

---//////////////// Serials By Customer /////////////////////////////////
IF @SerialType = 2 
BEGIN
	--/////// Invoice ///////////////////////////////
	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	Declare @tmpTbl Table (CompNo smallint, SalesmanNo int, TrYear smallint, CustomerNo bigint, MaxInvNo int, FromNo int, ToNo int, MaxInvNo2 int)

	INSERT INTO @tmpTbl
	SELECT Ytbl.CompNo, Ytbl.SalesmanNo, Ytbl.VouYear, Ytbl.CustomerNo, Ytbl.MaxInvNo, 
			Ytbl.FromNo, Ytbl.ToNo, Max(VouNo) AS MaxInvNo2
	FROM( 
	SELECT Xtbl.CompNo, Xtbl.SalesmanNo, Xtbl.VouYear, Xtbl.CustomerNo, Xtbl.MaxInvNo, 
			SalesPersonNotbookTransactionsSerials.FromNo, SalesPersonNotbookTransactionsSerials.ToNo
	FROM(
	SELECT  CompNo, SalesmanNo, VouYear, CustomerNo, MAX(VouNo) AS MaxInvNo
	FROM            OSFA_DB.dbo.OT_InvoiceHF
	WHERE        (CompNo = @CompNo) AND (VouType = 1) AND (VouYear = Year(@SendDate)) AND (SalesmanNo = @SalesmanNo)
	Group By CompNo, SalesmanNo, VouYear,CustomerNo
	) AS Xtbl Inner Join SalesPersonNotbookTransactionsSerials on
		Xtbl.CompNo = SalesPersonNotbookTransactionsSerials.CompanyID AND
		Xtbl.SalesmanNo = SalesPersonNotbookTransactionsSerials.SalesPersonID AND 
		Xtbl.VouYear = SalesPersonNotbookTransactionsSerials.SerYear
		AND (NextSerial <= ToNo) AND (MaxInvNo BETWEEN FromNo AND ToNo) AND (SerType = 1)
	) AS Ytbl Inner Join OSFA_DB.dbo.OT_InvoiceHF AS i on
		Ytbl.CompNo = i.CompNo AND
		Ytbl.VouYear = i.VouYear AND
		1 = i.VouType AND
		VouNo between FromNo and ToNo
	Group by Ytbl.CompNo, Ytbl.SalesmanNo, Ytbl.VouYear, Ytbl.CustomerNo, Ytbl.MaxInvNo, 
			Ytbl.FromNo, Ytbl.ToNo

	UPDATe SalesPersonNotbookTransactionsSerials
	SET NextSerial = Case When i.MaxInvNo < i.MaxInvNo2 then i.MaxInvNo else i.MaxInvNo2 end + 1,
		IsSuspended = Case When (Case When i.MaxInvNo < i.MaxInvNo2 then i.MaxInvNo else i.MaxInvNo2 end + 1) > SalesPersonNotbookTransactionsSerials.ToNo Then 1 else 0 end
	from @tmpTbl as i inner join SalesPersonNotbookTransactionsSerials on
		i.CompNo = SalesPersonNotbookTransactionsSerials.CompanyID AND
		i.SalesmanNo = SalesPersonNotbookTransactionsSerials.SalesPersonID AND
		i.TrYear = SalesPersonNotbookTransactionsSerials.SerYear
		AND (SalesPersonNotbookTransactionsSerials.NextSerial <= SalesPersonNotbookTransactionsSerials.ToNo) AND 
		(i.MaxInvNo BETWEEN SalesPersonNotbookTransactionsSerials.FromNo AND SalesPersonNotbookTransactionsSerials.ToNo) 
		AND (SalesPersonNotbookTransactionsSerials.SerType = 1) and isnull(IsSuspended,0) = 0

	--/////// Return Invoice ///////////////////////
	DELETE FROM @tmpTbl

	INSERT INTO @tmpTbl
	SELECT Ytbl.CompNo, Ytbl.SalesmanNo, Ytbl.VouYear, Ytbl.CustomerNo, Ytbl.MaxInvNo, 
			Ytbl.FromNo, Ytbl.ToNo, Max(VouNo) AS MaxInvNo2
	FROM( 
	SELECT Xtbl.CompNo, Xtbl.SalesmanNo, Xtbl.VouYear, Xtbl.CustomerNo, Xtbl.MaxInvNo, 
			SalesPersonNotbookTransactionsSerials.FromNo, SalesPersonNotbookTransactionsSerials.ToNo
	FROM(
	SELECT  CompNo, SalesmanNo, VouYear, CustomerNo, MAX(VouNo) AS MaxInvNo
	FROM            OSFA_DB.dbo.OT_InvoiceHF
	WHERE        (CompNo = @CompNo) AND (VouType = 2) AND (VouYear = Year(@SendDate)) AND (SalesmanNo = @SalesmanNo)
	Group By CompNo, SalesmanNo, VouYear,CustomerNo
	) AS Xtbl Inner Join SalesPersonNotbookTransactionsSerials on
		Xtbl.CompNo = SalesPersonNotbookTransactionsSerials.CompanyID AND
		Xtbl.SalesmanNo = SalesPersonNotbookTransactionsSerials.SalesPersonID AND 
		Xtbl.VouYear = SalesPersonNotbookTransactionsSerials.SerYear
		AND (NextSerial <= ToNo) AND (MaxInvNo BETWEEN FromNo AND ToNo) AND (SerType = 2)
	) AS Ytbl Inner Join OSFA_DB.dbo.OT_InvoiceHF AS i on
		Ytbl.CompNo = i.CompNo AND
		Ytbl.VouYear = i.VouYear AND
		2 = i.VouType AND
		VouNo between FromNo and ToNo
	Group by Ytbl.CompNo, Ytbl.SalesmanNo, Ytbl.VouYear, Ytbl.CustomerNo, Ytbl.MaxInvNo, 
			Ytbl.FromNo, Ytbl.ToNo

	UPDATe SalesPersonNotbookTransactionsSerials
	SET NextSerial = Case When i.MaxInvNo < i.MaxInvNo2 then i.MaxInvNo else i.MaxInvNo2 end + 1,
		IsSuspended = Case When (Case When i.MaxInvNo < i.MaxInvNo2 then i.MaxInvNo else i.MaxInvNo2 end + 1) > SalesPersonNotbookTransactionsSerials.ToNo Then 1 else 0 end
	from @tmpTbl as i inner join SalesPersonNotbookTransactionsSerials on
		i.CompNo = SalesPersonNotbookTransactionsSerials.CompanyID AND
		i.SalesmanNo = SalesPersonNotbookTransactionsSerials.SalesPersonID AND
		i.TrYear = SalesPersonNotbookTransactionsSerials.SerYear
		AND (SalesPersonNotbookTransactionsSerials.NextSerial <= SalesPersonNotbookTransactionsSerials.ToNo) AND 
		(i.MaxInvNo BETWEEN SalesPersonNotbookTransactionsSerials.FromNo AND SalesPersonNotbookTransactionsSerials.ToNo) 
		AND (SalesPersonNotbookTransactionsSerials.SerType = 2) and isnull(IsSuspended,0) = 0

	--/////// Receipt //////////////////////////////
	DELETE FROM @tmpTbl

	INSERT INTO @tmpTbl
	SELECT Ytbl.CompNo, Ytbl.SalesmanNo, Ytbl.VouYear, Ytbl.CustomerNo, Ytbl.MaxInvNo, 
			Ytbl.FromNo, Ytbl.ToNo, Max(VouNo) AS MaxInvNo2
	FROM( 
	SELECT Xtbl.CompNo, Xtbl.SalesmanNo, Xtbl.VouYear, Xtbl.CustomerNo, Xtbl.MaxInvNo, 
			SalesPersonNotbookTransactionsSerials.FromNo, SalesPersonNotbookTransactionsSerials.ToNo
	FROM(
	SELECT  CompNo, SalesmanNo, VouYear, CustomerNo, MAX(VouNo) AS MaxInvNo
	FROM            OSFA_DB.dbo.OT_Payments
	WHERE        (CompNo = @CompNo) AND (VouType = 3) AND (VouYear = Year(@SendDate)) AND (SalesmanNo = @SalesmanNo)
	Group By CompNo, SalesmanNo, VouYear,CustomerNo
	) AS Xtbl Inner Join SalesPersonNotbookTransactionsSerials on
		Xtbl.CompNo = SalesPersonNotbookTransactionsSerials.CompanyID AND
		Xtbl.SalesmanNo = SalesPersonNotbookTransactionsSerials.SalesPersonID AND 
		Xtbl.VouYear = SalesPersonNotbookTransactionsSerials.SerYear
		AND (NextSerial <= ToNo) AND (MaxInvNo BETWEEN FromNo AND ToNo) AND (SerType = 3)
	) AS Ytbl Inner Join OSFA_DB.dbo.OT_Payments AS i on
		Ytbl.CompNo = i.CompNo AND
		Ytbl.VouYear = i.VouYear AND
		3 = i.VouType AND
		VouNo between FromNo and ToNo
	Group by Ytbl.CompNo, Ytbl.SalesmanNo, Ytbl.VouYear, Ytbl.CustomerNo, Ytbl.MaxInvNo, 
			Ytbl.FromNo, Ytbl.ToNo

	UPDATe SalesPersonNotbookTransactionsSerials
	SET NextSerial = Case When i.MaxInvNo < i.MaxInvNo2 then i.MaxInvNo else i.MaxInvNo2 end + 1,
		IsSuspended = Case When (Case When i.MaxInvNo < i.MaxInvNo2 then i.MaxInvNo else i.MaxInvNo2 end + 1) > SalesPersonNotbookTransactionsSerials.ToNo Then 1 else 0 end
	from @tmpTbl as i inner join SalesPersonNotbookTransactionsSerials on
		i.CompNo = SalesPersonNotbookTransactionsSerials.CompanyID AND
		i.SalesmanNo = SalesPersonNotbookTransactionsSerials.SalesPersonID AND
		i.TrYear = SalesPersonNotbookTransactionsSerials.SerYear
		AND (SalesPersonNotbookTransactionsSerials.NextSerial <= SalesPersonNotbookTransactionsSerials.ToNo) AND 
		(i.MaxInvNo BETWEEN SalesPersonNotbookTransactionsSerials.FromNo AND SalesPersonNotbookTransactionsSerials.ToNo) 
		AND (SalesPersonNotbookTransactionsSerials.SerType = 3) and isnull(IsSuspended,0) = 0
	--///
	INSERT INTO [OSFA_DB].[dbo].[OT_SalesmanNotebookSerials]
           ([CompNo]
           ,[SalesmanNo]
           ,[SerYear]
           ,[SerType]
           ,[NotebookNo]
           ,[FromNo]
           ,[ToNo]
           ,[NextSerial]
		   ,[CustomerNo])
	SELECT        CompanyID, SalesPersonID, SerYear, SerType, NotbookNo, FromNo, ToNo, NextSerial,CustomerID
	FROM            SalesPersonNotbookTransactionsSerials
	WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (SerYear = Year(@SendDate)) AND (NextSerial <= ToNo) AND (IsNull(IsSuspended,0) = 0)
	ORDER BY NotbookNo

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_SalesmanNotebookSerials - Notebook Serial By Customer [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
END
--/////////// BONUS TARGET INFORMATION //////////////////////////////////////////////

IF @ClientActive = 27 OR @ClientActive = 30 Or @ClientActive = 136 Or @ClientActive= 50  Or @ClientActive= 41 or @ClientActive=82
BEGIN
	goto Skip_BONUSTARGET
END

SET @BeginTime = Convert(varchar(20),GetDate(),108)
DECLARE @UseSalesmanItemBonusTargetByCustomer varchar(50)=dbo.Fun_GetSalesmanSysOpValue(@CompNo,@SalesmanNo,625)

IF @ClientActive = 17 
BEGIN

INSERT INTO OSFA_DB.dbo.OT_SalesmanItemBonusTarget (CompNo, SalesmanNo, BonusYear, BonusMonth, ItemNo, Unit, Qty, MaxQty)
select CompanyID, SalesPersonID,TrYear,TrMonth,ItemCode,UnitID, SUM(Qty) as Qty, SUM(MaxQty) as MaxQty
FROM(
select CompanyID, SalesPersonID,YEAR(@SendDate) as TrYear,MONTH(@SendDate) as TrMonth,ItemCode,UnitID, SUM(Bonus) AS Qty, 0 as MaxQty 
FROM(
SELECT     TransactionsHeaders.CompanyID, TransactionsHeaders.SalesPersonID, TransactionsDetails.ItemCode, isnull(abs(SUM(TransactionsDetails.Bonus)),0) AS BONUS,
			TransactionsDetails.UnitID
FROM         TransactionsHeaders INNER JOIN
                      TransactionsDetails ON TransactionsHeaders.CompanyID = TransactionsDetails.CompanyID AND 
                      TransactionsHeaders.TransactionTypeID = TransactionsDetails.TransactionTypeID AND 
                      TransactionsHeaders.TransactionYear = TransactionsDetails.TransactionYear AND TransactionsHeaders.TransactionNo = TransactionsDetails.TransactionNo
WHERE     (TransactionsHeaders.TransactionTypeID = 1) AND (TransactionsHeaders.TransactionYear = Year(@SendDate)) AND (MONTH(TransactionsHeaders.TransactionDate) = Month(GetDate()))
and ItemCode in (select ItemCode from SalesPersonItemBonusTarget where CompanyID= @CompNo and SalesPersonID = @SalesmanNo and TargetYear = Year(@SendDate))
GROUP BY TransactionsHeaders.CompanyID, TransactionsHeaders.SalesPersonID, TransactionsDetails.ItemCode,TransactionsDetails.UnitID
HAVING      (TransactionsHeaders.CompanyID = @CompNo) AND (TransactionsHeaders.SalesPersonID = @SalesmanNo) AND (ABS(SUM(TransactionsDetails.Bonus)) > 0)
	
union All

SELECT     OrdersHeaders.CompanyID, OrdersHeaders.SalesPersonID, OrdersDetails.ItemCode, isnull(abs(SUM(OrdersDetails.Bonus)),0) AS BONUS,
			OrdersDetails.UnitID
FROM         OrdersHeaders INNER JOIN
                      OrdersDetails ON OrdersHeaders.CompanyID = OrdersDetails.CompanyID AND                        
                      OrdersHeaders.OrderYear = OrdersDetails.OrderYear AND OrdersHeaders.OrderNo = OrdersDetails.OrderNo
WHERE      (OrdersHeaders.OrderYear = Year(@SendDate)) AND (MONTH(OrdersHeaders.OrderDate) = Month(GetDate()))
and ItemCode in (select ItemCode from SalesPersonItemBonusTarget where CompanyID= @CompNo and SalesPersonID = @SalesmanNo and TargetYear = Year(@SendDate))
GROUP BY OrdersHeaders.CompanyID, OrdersHeaders.SalesPersonID, OrdersDetails.ItemCode,OrdersDetails.UnitID
HAVING      (OrdersHeaders.CompanyID = @CompNo) AND (OrdersHeaders.SalesPersonID = @SalesmanNo) AND (ABS(SUM(OrdersDetails.Bonus)) > 0)
	
union All

SELECT     TransactionsHeaders.CompanyID,TransactionsHeaders.SalesPersonID,TransactionsPromotions.ItemNo, isnull(SUM(TransactionsPromotions.Bonus),0)*-1 as Bonus,
			TransactionsPromotions.UnitCode
FROM         TransactionsPromotions INNER JOIN
                      TransactionsHeaders ON TransactionsPromotions.CompanyID = TransactionsHeaders.CompanyID AND 
                      TransactionsPromotions.TrTypeID = TransactionsHeaders.TransactionTypeID AND TransactionsPromotions.TrYear = TransactionsHeaders.TransactionYear AND 
                      TransactionsPromotions.TrNo = TransactionsHeaders.TransactionNo
WHERE     (TransactionsHeaders.TransactionTypeID = 1) AND (TransactionsHeaders.TransactionYear = Year(@SendDate)) AND (MONTH(TransactionsHeaders.TransactionDate) = Month(GetDate()))                      
and ItemNo in (select ItemCode from SalesPersonItemBonusTarget where CompanyID= @CompNo and SalesPersonID = @SalesmanNo and TargetYear = Year(@SendDate))
GROUP BY TransactionsHeaders.CompanyID,TransactionsHeaders.SalesPersonID,TransactionsPromotions.ItemNo,TransactionsPromotions.UnitCode
HAVING      (TransactionsHeaders.CompanyID = @CompNo) AND (TransactionsHeaders.SalesPersonID = @SalesmanNo) AND (ABS(SUM(TransactionsPromotions.Bonus)) > 0)

union All

SELECT     OrdersHeaders.CompanyID,OrdersHeaders.SalesPersonID,TransactionsPromotions.ItemNo, isnull(SUM(TransactionsPromotions.Bonus),0)*-1 as Bonus,
			TransactionsPromotions.UnitCode
FROM         TransactionsPromotions INNER JOIN
                      OrdersHeaders ON TransactionsPromotions.CompanyID = OrdersHeaders.CompanyID AND                       
                       TransactionsPromotions.TrYear = OrdersHeaders.OrderYear AND 
                      TransactionsPromotions.TrNo = OrdersHeaders.OrderNo
WHERE     (TransactionsPromotions.TrTypeID = 3) AND (OrdersHeaders.OrderYear = Year(@SendDate)) AND (MONTH(OrdersHeaders.OrderDate) = Month(GetDate()))                      
and ItemNo in (select ItemCode from SalesPersonItemBonusTarget where CompanyID= @CompNo and SalesPersonID = @SalesmanNo and TargetYear = Year(@SendDate))
GROUP BY OrdersHeaders.CompanyID,OrdersHeaders.SalesPersonID,TransactionsPromotions.ItemNo,TransactionsPromotions.UnitCode
HAVING      (OrdersHeaders.CompanyID = @CompNo) AND (OrdersHeaders.SalesPersonID = @SalesmanNo) AND (ABS(SUM(TransactionsPromotions.Bonus)) > 0)
	
	) as Xtbl
group by CompanyID, SalesPersonID,itemcode,UnitID

Union All

SELECT     CompanyID, SalesPersonID, TargetYear, MONTH(@SendDate),ItemCode, UnitID , 0 as Qty,
			CASE WHEN Month(@SendDate) BETWEEN 1 AND 6 THEN CASE WHEN Month(@SendDate) 
                      = 1 THEN SalesPersonItemBonusTarget.M1 ELSE CASE WHEN Month(@SendDate) = 2 THEN SalesPersonItemBonusTarget.M2 ELSE CASE WHEN Month(@SendDate)
                       = 3 THEN SalesPersonItemBonusTarget.M3 ELSE CASE WHEN Month(@SendDate) = 4 THEN M4 ELSE CASE WHEN Month(@SendDate) 
                      = 5 THEN SalesPersonItemBonusTarget.M5 ELSE CASE WHEN Month(@SendDate) = 6 THEN M6 END END END END END END ELSE CASE WHEN Month(@SendDate)
                       = 7 THEN SalesPersonItemBonusTarget.M7 ELSE CASE WHEN Month(@SendDate) = 8 THEN M8 ELSE CASE WHEN Month(@SendDate) 
                      = 9 THEN SalesPersonItemBonusTarget.M9 ELSE CASE WHEN Month(@SendDate) 
                      = 10 THEN SalesPersonItemBonusTarget.M10 ELSE CASE WHEN Month(@SendDate) 
                      = 11 THEN SalesPersonItemBonusTarget.M11 ELSE CASE WHEN Month(@SendDate) 
                      = 12 THEN SalesPersonItemBonusTarget.M12 END END END END END END END AS MaxQty
                      
FROM         SalesPersonItemBonusTarget   
WHERE CompanyID = @CompNo and SalesPersonID = @SalesmanNo AND TargetYear = YEAR(@SendDate)
) as Ytbl
Group by  CompanyID, SalesPersonID,TrYear,TrMonth,ItemCode,UnitID

END

IF @UseSalesmanItemBonusTargetByCustomer='1' --////// Al Wafi
BEGIN

DELETE FROM [OSFA_DB].[dbo].[OT_SalesmanItemBonusTargetByCustomer] WHERE(CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)


INSERT INTO OSFA_DB.dbo.[OT_SalesmanItemBonusTargetByCustomer] (CompNo, SalesmanNo, BonusYear, BonusMonth,CustomerID, ItemNo, Unit, Qty, MaxQty)
SELECT CompanyID, SalesmanNo, TrYear, TrMonth,CustomerID, ItemCode, Unit, SUM(Qty) AS Qty, SUM(MaxQty) AS MaxQty
		FROM(
			SELECT        CompanyID, @SalesmanNo AS SalesmanNo, TransactionYear AS TrYear, TrMonth,CustomerID, ItemCode, dbo.GetItemUnitBySerial(CompanyID,ItemCode, 6) AS Unit, SUM(Bonus) AS Qty, 0 AS MaxQty
			FROM            dbo.[Fun_GetInvoiceAndOrderForTargetBonus](@CompNo, YEAR(@SendDate),@SalesmanNo,@SalesmanNo,'0','zzzzzzzzzzzzzz',0,999999999) AS Fun_GetInvoiceAndOrderForTargetBonus_1
			WHERE        (TrMonth = MONTH(@SendDate))   AND Bonus<>0
			GROUP BY CompanyID, TransactionYear, TrMonth, CustomerID, ItemCode

			UNION ALL

			SELECT        Items.CompanyID, SalesPersonItemBonusTargetByCustomer.SalesPersonID, SalesPersonItemBonusTargetByCustomer.TargetYear, MONTH(@SendDate) AS TargetMonth,SalesPersonItemBonusTargetByCustomer.CustomerID, Items.ItemCode, 
									dbo.GetItemUnitBySerial(@CompNo, Items.ItemCode, 6) AS UnitID, 
									 0 AS Qty, 
									 dbo.GetItemSmallUnitQty(@CompNo, Items.ItemCode, SalesPersonItemBonusTargetByCustomer.UnitID, 
									 CASE MONTH(@SendDate) WHEN 1 THEN M1 WHEN 2 THEN M2 WHEN 3 THEN M3 WHEN 4 THEN M4 WHEN 5 THEN M5 WHEN 6 THEN M6 WHEN 7 THEN M7 WHEN 8 THEN M8 WHEN 9 THEN M9 WHEN 10 THEN M10 WHEN 11 THEN
									  M11 WHEN 12 THEN M12 END) AS MaxQty
			FROM            SalesPersonItemBonusTargetByCustomer INNER JOIN
									 Items ON SalesPersonItemBonusTargetByCustomer.CompanyID = Items.CompanyID AND SalesPersonItemBonusTargetByCustomer.ItemCode = Items.ItemCode  INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON SalesPersonItemBonusTargetByCustomer.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 SalesPersonItemBonusTargetByCustomer.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo 
			WHERE        (Items.CompanyID = @CompNo) AND (SalesPersonItemBonusTargetByCustomer.SalesPersonID = @SalesmanNo) AND (SalesPersonItemBonusTargetByCustomer.TargetYear = YEAR(@SendDate)) 
			AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
	
		) AS Xtbl 
		GROUP BY CompanyID, SalesmanNo, TrYear, TrMonth,Xtbl.CustomerID, ItemCode, Unit
		HAVING  SUM(MaxQty)<>0
		 

END

ELSE
BEGIN 
	DECLARE @UseItemBonusTargetSalesmanGroup varchar(50)=dbo.Fun_GetSalesmanSysOpValue(@CompNo,@SalesmanNo,427)
	DECLARE @UseItemBonusTargetGroup bit=0
	SELECT        @UseItemBonusTargetGroup=ISNULL(UseItemBonusTargetGroup,0)
	FROM            CompanyParameters
	WHERE        (CompanyID = @CompNo)

	IF @UseItemBonusTargetGroup<>0
	BEGIN
	DELETE FROM [OSFA_DB].[dbo].[OT_SalesmanItemBonusTarget] WHERE(CompNo = @CompNo) AND (SalesmanNo = @SalesmanGroupID)

	DELETE FROM [OSFA_DB].[dbo].[OT_SalesmanItemBonusTarget] WHERE(CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
	

		INSERT INTO OSFA_DB.dbo.OT_SalesmanItemBonusTarget (CompNo, SalesmanNo, BonusYear, BonusMonth, ItemNo, Unit, Qty, MaxQty)
		SELECT CompanyID, SalesmanNo, TrYear, TrMonth, ItemCode, Unit, SUM(Qty) AS Qty, SUM(MaxQty) AS MaxQty
		FROM(
			SELECT   DISTINCT     CompanyID, SalesmanNo, TrYear, TrMonth, ItemCode, ISNULL(dbo.GetItemUnitBySerial(CompanyID,ItemCode, 6),'1') AS Unit, Qty, 0 AS MaxQty
			FROM            dbo.Fun_GetSalesmanBonusItemForTarget(@CompNo, YEAR(@SendDate),@SalesmanNo,@SalesmanNo,'0','zzzzzzzzzzzzzz',@SalesmanGroupID,@SalesmanGroupID,(CASE WHEN @UseItemBonusTargetSalesmanGroup='1' THEN 1 ELSE 0 END))
			WHERE        (TrMonth = MONTH(@SendDate))   and ISNULL(ItemCode,'0') <> '0' --AND (SalesmanNo = @SalesmanNo)
			UNION ALL
			SELECT     DISTINCT   Items.CompanyID, SalesPersonItemBonusTarget.SalesPersonID, SalesPersonItemBonusTarget.TargetYear, MONTH(@SendDate) AS TargetMonth, Items.ItemBonusTargetGroupID, 
									dbo.GetItemUnitBySerial(@CompNo, Items.ItemCode, 6) AS UnitID, 
									 0 AS Qty, 
									 dbo.GetItemSmallUnitQty(@CompNo, Items.ItemCode, SalesPersonItemBonusTarget.UnitID, 
									 CASE MONTH(@SendDate) WHEN 1 THEN M1 WHEN 2 THEN M2 WHEN 3 THEN M3 WHEN 4 THEN M4 WHEN 5 THEN M5 WHEN 6 THEN M6 WHEN 7 THEN M7 WHEN 8 THEN M8 WHEN 9 THEN M9 WHEN 10 THEN M10 WHEN 11 THEN
									  M11 WHEN 12 THEN M12 END) AS MaxQty
			FROM            SalesPersonItemBonusTarget INNER JOIN
									 Items ON SalesPersonItemBonusTarget.CompanyID = Items.CompanyID AND SalesPersonItemBonusTarget.ItemCode = Items.ItemBonusTargetGroupID
			WHERE        (Items.CompanyID = @CompNo) AND (SalesPersonItemBonusTarget.SalesPersonID = @SalesmanNo) AND (SalesPersonItemBonusTarget.TargetYear = YEAR(@SendDate)) AND @UseItemBonusTargetSalesmanGroup<>'1'
			UNION ALL
			SELECT     DISTINCT   Items.CompanyID, SalesPersonGroupItemBonusTarget.SalesPersonGroupID, SalesPersonGroupItemBonusTarget.TargetYear, MONTH(@SendDate) AS TargetMonth, Items.ItemBonusTargetGroupID, 
									dbo.GetItemUnitBySerial(@CompNo, Items.ItemCode, 6) AS UnitID, 
									 0 AS Qty, 
									 dbo.GetItemSmallUnitQty(@CompNo, Items.ItemCode, SalesPersonGroupItemBonusTarget.UnitID, 
									 CASE MONTH(@SendDate) WHEN 1 THEN M1 WHEN 2 THEN M2 WHEN 3 THEN M3 WHEN 4 THEN M4 WHEN 5 THEN M5 WHEN 6 THEN M6 WHEN 7 THEN M7 WHEN 8 THEN M8 WHEN 9 THEN M9 WHEN 10 THEN M10 WHEN 11 THEN
									  M11 WHEN 12 THEN M12 END) AS MaxQty
			FROM            SalesPersonGroupItemBonusTarget INNER JOIN
									 Items ON SalesPersonGroupItemBonusTarget.CompanyID = Items.CompanyID AND SalesPersonGroupItemBonusTarget.ItemCode = Items.ItemBonusTargetGroupID
			WHERE        (Items.CompanyID = @CompNo) AND (SalesPersonGroupItemBonusTarget.SalesPersonGroupID = @SalesmanGroupID) AND (SalesPersonGroupItemBonusTarget.TargetYear = YEAR(@SendDate)) AND @UseItemBonusTargetSalesmanGroup='1'
		) AS Xtbl
		GROUP BY CompanyID, SalesmanNo, TrYear, TrMonth, ItemCode, Unit


	END
	ELSE
	BEGIN

		INSERT INTO OSFA_DB.dbo.OT_SalesmanItemBonusTarget (CompNo, SalesmanNo, BonusYear, BonusMonth, ItemNo, Unit, Qty, MaxQty)
		SELECT CompanyID, SalesmanNo, TrYear, TrMonth, ItemCode, Unit, SUM(Qty) AS Qty, SUM(MaxQty) AS MaxQty
		FROM(
			SELECT        CompanyID, SalesmanNo, TrYear, TrMonth, ItemCode, dbo.GetItemUnitBySerial(CompanyID,ItemCode, 6) AS Unit, Qty, 0 AS MaxQty
			FROM            dbo.Fun_GetSalesmanBonusItemForTarget(@CompNo, YEAR(@SendDate),@SalesmanNo,@SalesmanNo,'0','zzzzzzzzzzzzzz',@SalesmanGroupID,@SalesmanGroupID,(CASE WHEN @UseItemBonusTargetSalesmanGroup='1' THEN 1 ELSE 0 END))
			WHERE        (TrMonth = MONTH(@SendDate)) AND (SalesmanNo = @SalesmanNo)
			UNION ALL
			SELECT        Items.CompanyID, SalesPersonItemBonusTarget.SalesPersonID, SalesPersonItemBonusTarget.TargetYear, MONTH(@SendDate) AS TargetMonth, Items.ItemCode, 
									dbo.GetItemUnitBySerial(@CompNo, Items.ItemCode, 6) AS UnitID, 
									 0 AS Qty, 
									 dbo.GetItemSmallUnitQty(@CompNo, Items.ItemCode, SalesPersonItemBonusTarget.UnitID, 
									 CASE MONTH(@SendDate) WHEN 1 THEN M1 WHEN 2 THEN M2 WHEN 3 THEN M3 WHEN 4 THEN M4 WHEN 5 THEN M5 WHEN 6 THEN M6 WHEN 7 THEN M7 WHEN 8 THEN M8 WHEN 9 THEN M9 WHEN 10 THEN M10 WHEN 11 THEN
									  M11 WHEN 12 THEN M12 END) AS MaxQty
			FROM            SalesPersonItemBonusTarget INNER JOIN
									 Items ON SalesPersonItemBonusTarget.CompanyID = Items.CompanyID AND SalesPersonItemBonusTarget.ItemCode = Items.ItemCode
			WHERE        (Items.CompanyID = @CompNo) AND (SalesPersonItemBonusTarget.SalesPersonID = @SalesmanNo) AND (SalesPersonItemBonusTarget.TargetYear = YEAR(@SendDate)) AND @UseItemBonusTargetSalesmanGroup<>'1'
			UNION ALL
			SELECT        Items.CompanyID, SalesPersonGroupItemBonusTarget.SalesPersonGroupID , SalesPersonGroupItemBonusTarget.TargetYear, MONTH(@SendDate) AS TargetMonth, Items.ItemCode, 
									dbo.GetItemUnitBySerial(@CompNo, Items.ItemCode, 6) AS UnitID, 
									 0 AS Qty, 
									 dbo.GetItemSmallUnitQty(@CompNo, Items.ItemCode, SalesPersonGroupItemBonusTarget.UnitID, 
									 CASE MONTH(@SendDate) WHEN 1 THEN M1 WHEN 2 THEN M2 WHEN 3 THEN M3 WHEN 4 THEN M4 WHEN 5 THEN M5 WHEN 6 THEN M6 WHEN 7 THEN M7 WHEN 8 THEN M8 WHEN 9 THEN M9 WHEN 10 THEN M10 WHEN 11 THEN
									  M11 WHEN 12 THEN M12 END) AS MaxQty
			FROM            SalesPersonGroupItemBonusTarget INNER JOIN
									 Items ON SalesPersonGroupItemBonusTarget.CompanyID = Items.CompanyID AND SalesPersonGroupItemBonusTarget.ItemCode = Items.ItemCode
			WHERE        (Items.CompanyID = @CompNo) AND (SalesPersonGroupItemBonusTarget.SalesPersonGroupID = @SalesmanGroupID) AND (SalesPersonGroupItemBonusTarget.TargetYear = YEAR(@SendDate))  AND @UseItemBonusTargetSalesmanGroup='1'
		) AS Xtbl
		GROUP BY CompanyID, SalesmanNo, TrYear, TrMonth, ItemCode, Unit

	END
/*
INSERT INTO OSFA_DB.dbo.OT_SalesmanItemBonusTarget (CompNo, SalesmanNo, BonusYear, BonusMonth, ItemNo, Unit, Qty, MaxQty)
SELECT CompanyID,SalesPersonID,TargetYear,TargetMonth,ItemCode,UnitID, SUM(Qty) AS Qty, SUM(MaxQty) AS MaxQty
FROM(
SELECT Items.CompanyID, SalesPersonID, TargetYear, Month(@SendDate) AS TargetMonth,Items.ItemCode,dbo.GetItemUnitBySerial (@CompNo, Items.ItemCode,6) AS UnitID, 0 AS Qty, 		
	dbo.GetItemSmallUnitQty (@CompNo, Items.ItemCode, SalesPersonItemBonusTarget.UnitID, CASE MONTH(@SendDate) WHEN 1 THEN M1 WHEN 2 THEN M2 WHEN 3 THEN M3 WHEN 4 THEN M4 WHEN 5 THEN M5 WHEN 6 THEN M6 WHEN 7 THEN M7 WHEN 8 THEN M8 WHEN 9 THEN M9 WHEN 10 THEN M10 WHEN 11 THEN M11 WHEN 12 THEN M12 END) AS MaxQty
FROM SalesPersonItemBonusTarget INNER JOIN Items ON
		SalesPersonItemBonusTarget.CompanyID = Items.CompanyID AND
		SalesPersonItemBonusTarget.ItemCode = Items.ItemCode
WHERE Items.CompanyID = @CompNo and SalesPersonID = @SalesmanNo and TargetYear = Year(@SendDate)

UNION ALL

	SELECT CompanyID, SalesPersonID, TransactionYear, TargetMonth,ItemCode,dbo.GetItemUnitBySerial (@CompNo, ItemCode,6) AS UnitID, SUM(Qty) AS Qty,SUM(MaxQty) AS MaxQty
	FROM(
		SELECT  distinct    TransactionsHeaders.CompanyID, TransactionsHeaders.SalesPersonID, TransactionsHeaders.TransactionYear, MONTH(@SendDate) AS TargetMonth,
					TransactionsDetails.ItemCode, TransactionsDetails.UnitID, 		 
					ABS((dbo.GetItemSmallUnitQty (@CompNo, TransactionsDetails.ItemCode, TransactionsDetails.UnitID, dbo.GetItemOrgUnitQty(@CompNo, TransactionsDetails.ItemCode, TransactionsDetails.UnitID, CASE WHEN @ClientActive = 11 THEN TransactionsDetails.Bonus + TransactionsDetails.Quantity ELSE TransactionsDetails.Bonus END)))) AS Qty , 0 AS MaxQty	
		FROM            TransactionsHeaders INNER JOIN
								 TransactionsDetails ON TransactionsHeaders.CompanyID = TransactionsDetails.CompanyID AND TransactionsHeaders.TransactionTypeID = TransactionsDetails.TransactionTypeID AND 
								 TransactionsHeaders.TransactionYear = TransactionsDetails.TransactionYear AND TransactionsHeaders.TransactionNo = TransactionsDetails.TransactionNo INNER JOIN
								 TransactionsPromotions ON TransactionsHeaders.CompanyID = TransactionsPromotions.CompanyID AND TransactionsHeaders.TransactionTypeID = TransactionsPromotions.TrTypeID AND 
								 TransactionsHeaders.TransactionYear = TransactionsPromotions.TrYear AND TransactionsHeaders.TransactionNo = TransactionsPromotions.TrNo  INNER JOIN Items ON
								 TransactionsDetails.CompanyID = Items.CompanyID AND
								 TransactionsDetails.ItemCode = Items.ItemCode
		WHERE        (TransactionsDetails.CompanyID = @CompNo) 
					AND (TransactionsHeaders.SalesPersonID = @SalesmanNo) 
					AND (TransactionsHeaders.TransactionYear = YEAR(@SendDate)) 
					AND (TransactionsDetails.TransactionTypeID = 1) 
					AND (MONTH(TransactionsHeaders.TransactionDate) = MONTH(@SendDate)) 
					AND (TransactionsPromotions.InputItem = '') 
					AND (TransactionsPromotions.IncludeInTargetBonus = 1) 
					AND (ISNULL(TransactionsHeaders.IsVoid, 0) = 0) 
					AND (ISNULL(TransactionsHeaders.Approve, 0) = 1)
	) AS XXXtbl
	GROUP BY CompanyID, SalesPersonID, TransactionYear, TargetMonth,ItemCode,UnitID

UNION ALL
	SELECT CompanyID, SalesPersonID, OrderYear, TargetMonth,ItemCode,dbo.GetItemUnitBySerial (@CompNo, ItemCode,6) AS UnitID, SUM(Qty) AS Qty,SUM(MaxQty) AS MaxQty
	FROM(
		SELECT   distinct   OrdersHeaders.CompanyID, OrdersHeaders.SalesPersonID, OrdersHeaders.OrderYear, MONTH(@SendDate) AS TargetMonth,
					OrdersDetails.ItemCode, OrdersDetails.UnitID, 		 
					ABS((dbo.GetItemSmallUnitQty (@CompNo, OrdersDetails.ItemCode, OrdersDetails.UnitID, dbo.GetItemOrgUnitQty(@CompNo, OrdersDetails.ItemCode, OrdersDetails.UnitID, CASE WHEN @ClientActive = 11 THEN OrdersDetails.Bonus + OrdersDetails.Quantity ELSE OrdersDetails.Bonus END)))) AS Qty , 0 AS MaxQty	
		FROM            OrdersHeaders INNER JOIN
								 OrdersDetails ON OrdersHeaders.CompanyID = OrdersDetails.CompanyID AND 
								 OrdersHeaders.OrderYear = OrdersDetails.OrderYear AND OrdersHeaders.OrderNo = OrdersDetails.OrderNo INNER JOIN
								 TransactionsPromotions ON OrdersHeaders.CompanyID = TransactionsPromotions.CompanyID AND  
								 OrdersHeaders.OrderYear = TransactionsPromotions.TrYear AND OrdersHeaders.OrderNo = TransactionsPromotions.TrNo  INNER JOIN Items ON
								 OrdersDetails.CompanyID = Items.CompanyID AND
								 OrdersDetails.ItemCode = Items.ItemCode
		WHERE        (OrdersDetails.CompanyID = @CompNo) 
					AND (OrdersHeaders.SalesPersonID = @SalesmanNo) 
					AND (OrdersHeaders.OrderYear = YEAR(@SendDate)) 			
					AND (MONTH(OrdersHeaders.OrderDate) = MONTH(@SendDate)) 
					AND (TransactionsPromotions.TrTypeID = 3) 
					AND (TransactionsPromotions.InputItem = '') 
					AND (TransactionsPromotions.IncludeInTargetBonus = 1) 
					AND (ISNULL(OrdersHeaders.IsVoid, 0) = 0) 
					AND (ISNULL(OrdersHeaders.Approved, 0) = 1)		
		) AS XXtbl
	GROUP BY CompanyID, SalesPersonID, OrderYear, TargetMonth,ItemCode,UnitID	
) AS Xtbl
GROUP BY CompanyID,SalesPersonID,TargetYear,TargetMonth,ItemCode,UnitID
*/
/*
SELECT CompanyID, SalesPersonID, TargetYear, TargetMonth, ItemCode, UnitID,SUM (xtbl.Bonus) as Bonus , 
			       ABS(xtbl.MaxQty) as MaxQty

FROM
	(SELECT        SalesPersonItemBonusTarget.CompanyID, SalesPersonItemBonusTarget.SalesPersonID, SalesPersonItemBonusTarget.TargetYear, MONTH(@SendDate) AS TargetMonth, 
							 SalesPersonItemBonusTarget.ItemCode, SalesPersonItemBonusTarget.UnitID, 
							 --ABS(ISNULL(SUM(TransactionsDetails.Bonus), 0)) AS Bonus, 
							 ( dbo.GetItemSmallUnitQty(SalesPersonItemBonusTarget.CompanyID, SalesPersonItemBonusTarget.ItemCode, TransactionsDetails.UnitID, 
                dbo.GetItemOrgUnitQty(SalesPersonItemBonusTarget.CompanyID, SalesPersonItemBonusTarget.ItemCode, TransactionsDetails.UnitID,
							  ABS(ISNULL((CASE WHEN @ClientActive = 11
							  THEN TransactionsDetails.Bonus + TransactionsDetails.Quantity ELSE TransactionsDetails.Bonus END), 0)))
							  )) as Bonus		,
							  dbo.GetItemSmallUnitQty(SalesPersonItemBonusTarget.CompanyID, SalesPersonItemBonusTarget.ItemCode, SalesPersonItemBonusTarget.UnitID,
							  CASE WHEN Month(@SendDate) BETWEEN 1 AND 
							 6 THEN CASE WHEN Month(@SendDate) = 1 THEN SalesPersonItemBonusTarget.M1 ELSE CASE WHEN Month(@SendDate) = 2 THEN SalesPersonItemBonusTarget.M2 ELSE CASE WHEN Month(@SendDate) 
							 = 3 THEN SalesPersonItemBonusTarget.M3 ELSE CASE WHEN Month(@SendDate) = 4 THEN SalesPersonItemBonusTarget.M4 ELSE CASE WHEN Month(@SendDate) 
							 = 5 THEN SalesPersonItemBonusTarget.M5 ELSE CASE WHEN Month(@SendDate) = 6 THEN SalesPersonItemBonusTarget.M6 END END END END END END ELSE CASE WHEN Month(@SendDate) 
							 = 7 THEN SalesPersonItemBonusTarget.M7 ELSE CASE WHEN Month(@SendDate) = 8 THEN SalesPersonItemBonusTarget.M8 ELSE CASE WHEN Month(@SendDate) 
							 = 9 THEN SalesPersonItemBonusTarget.M9 ELSE CASE WHEN Month(@SendDate) = 10 THEN SalesPersonItemBonusTarget.M10 ELSE CASE WHEN Month(@SendDate) 
							 = 11 THEN SalesPersonItemBonusTarget.M11 ELSE CASE WHEN Month(@SendDate) = 12 THEN SalesPersonItemBonusTarget.M12 END END END END END END END) AS MaxQty
	FROM            TransactionsHeaders INNER JOIN
							 TransactionsDetails ON TransactionsHeaders.CompanyID = TransactionsDetails.CompanyID AND TransactionsHeaders.TransactionTypeID = TransactionsDetails.TransactionTypeID AND 
							 TransactionsHeaders.TransactionYear = TransactionsDetails.TransactionYear AND TransactionsHeaders.TransactionNo = TransactionsDetails.TransactionNo INNER JOIN
							 TransactionsPromotions ON TransactionsHeaders.CompanyID = TransactionsPromotions.CompanyID AND TransactionsHeaders.TransactionTypeID = TransactionsPromotions.TrTypeID AND 
							 TransactionsHeaders.TransactionYear = TransactionsPromotions.TrYear AND TransactionsHeaders.TransactionNo = TransactionsPromotions.TrNo RIGHT OUTER JOIN
							 SalesPersonItemBonusTarget ON TransactionsDetails.CompanyID = SalesPersonItemBonusTarget.CompanyID AND TransactionsDetails.TransactionYear = SalesPersonItemBonusTarget.TargetYear AND 
							 TransactionsDetails.ItemCode = SalesPersonItemBonusTarget.ItemCode AND TransactionsDetails.TransactionTypeID = 1 AND 
							 TransactionsHeaders.SalesPersonID = @SalesmanNo AND TransactionsHeaders.TransactionYear = YEAR(@SendDate) AND MONTH(TransactionsHeaders.TransactionDate) = MONTH(@SendDate)
							 AND TransactionsPromotions.InputItem = '' AND (TransactionsPromotions.IncludeInTargetBonus = 1) AND (ISNULL(TransactionsHeaders.IsVoid,0) = 0) AND (ISNULL(TransactionsHeaders.Approve,0) = 1)
	WHERE        (SalesPersonItemBonusTarget.CompanyID = @CompNo) AND (SalesPersonItemBonusTarget.SalesPersonID = @SalesmanNo) AND (SalesPersonItemBonusTarget.TargetYear = YEAR(@SendDate)) AND 
							 (CASE WHEN Month(@SendDate) BETWEEN 1 AND 6 THEN CASE WHEN Month(@SendDate) = 1 THEN SalesPersonItemBonusTarget.M1 ELSE CASE WHEN Month(@SendDate) = 2 THEN SalesPersonItemBonusTarget.M2 ELSE 
																		      CASE WHEN Month(@SendDate) = 3 THEN SalesPersonItemBonusTarget.M3 ELSE CASE WHEN Month(@SendDate) = 4 THEN SalesPersonItemBonusTarget.M4 ELSE 
																			  CASE WHEN Month(@SendDate) = 5 THEN SalesPersonItemBonusTarget.M5 ELSE CASE WHEN Month(@SendDate) = 6 THEN SalesPersonItemBonusTarget.M6 END END END END END END ELSE 
																			  CASE WHEN Month(@SendDate) = 7 THEN SalesPersonItemBonusTarget.M7 ELSE CASE WHEN Month(@SendDate) = 8 THEN SalesPersonItemBonusTarget.M8 ELSE 
																			  CASE WHEN Month(@SendDate) = 9 THEN SalesPersonItemBonusTarget.M9 ELSE CASE WHEN Month(@SendDate) = 10 THEN SalesPersonItemBonusTarget.M10 ELSE 
																			  CASE WHEN Month(@SendDate) = 11 THEN SalesPersonItemBonusTarget.M11 ELSE CASE WHEN Month(@SendDate) = 12 THEN SalesPersonItemBonusTarget.M12 END END END END END END END > 0)
	GROUP BY SalesPersonItemBonusTarget.CompanyID, SalesPersonItemBonusTarget.SalesPersonID, SalesPersonItemBonusTarget.TargetYear, SalesPersonItemBonusTarget.ItemCode, 
							  SalesPersonItemBonusTarget.M1, SalesPersonItemBonusTarget.M2, SalesPersonItemBonusTarget.M3, SalesPersonItemBonusTarget.M4, SalesPersonItemBonusTarget.M5, SalesPersonItemBonusTarget.M6, 
							 SalesPersonItemBonusTarget.M7, SalesPersonItemBonusTarget.M8, SalesPersonItemBonusTarget.M9, SalesPersonItemBonusTarget.M10, SalesPersonItemBonusTarget.M11, SalesPersonItemBonusTarget.M12,SalesPersonItemBonusTarget.UnitID,TransactionsDetails.UnitID,TransactionsDetails.Bonus,TransactionsDetails.Quantity
	union all

	SELECT        SalesPersonItemBonusTarget.CompanyID, SalesPersonItemBonusTarget.SalesPersonID, SalesPersonItemBonusTarget.TargetYear, MONTH(@SendDate) AS TargetMonth, 
							 SalesPersonItemBonusTarget.ItemCode, SalesPersonItemBonusTarget.UnitID,
							 --ABS(ISNULL(SUM(OrdersDetails.Bonus), 0)) AS Bonus, 							 
							 dbo.GetItemOrgUnitQty(SalesPersonItemBonusTarget.CompanyID, SalesPersonItemBonusTarget.ItemCode, SalesPersonItemBonusTarget.UnitID, ABS(ISNULL(SUM(CASE WHEN @ClientActive = 11 THEN OrdersDetails.Bonus + OrdersDetails.Quantity ELSE OrdersDetails.Bonus END), 0))) AS Bonus,
							 CASE WHEN Month(@SendDate) BETWEEN 1 AND 
							 6 THEN CASE WHEN Month(@SendDate) = 1 THEN SalesPersonItemBonusTarget.M1 ELSE CASE WHEN Month(@SendDate) = 2 THEN SalesPersonItemBonusTarget.M2 ELSE CASE WHEN Month(@SendDate) 
							 = 3 THEN SalesPersonItemBonusTarget.M3 ELSE CASE WHEN Month(@SendDate) = 4 THEN SalesPersonItemBonusTarget.M4 ELSE CASE WHEN Month(@SendDate) 
							 = 5 THEN SalesPersonItemBonusTarget.M5 ELSE CASE WHEN Month(@SendDate) = 6 THEN SalesPersonItemBonusTarget.M6 END END END END END END ELSE CASE WHEN Month(@SendDate) 
							 = 7 THEN SalesPersonItemBonusTarget.M7 ELSE CASE WHEN Month(@SendDate) = 8 THEN SalesPersonItemBonusTarget.M8 ELSE CASE WHEN Month(@SendDate) 
							 = 9 THEN SalesPersonItemBonusTarget.M9 ELSE CASE WHEN Month(@SendDate) = 10 THEN SalesPersonItemBonusTarget.M10 ELSE CASE WHEN Month(@SendDate) 
							 = 11 THEN SalesPersonItemBonusTarget.M11 ELSE CASE WHEN Month(@SendDate) = 12 THEN SalesPersonItemBonusTarget.M12 END END END END END END END AS MaxQty
	FROM            OrdersHeaders INNER JOIN
							 OrdersDetails ON OrdersHeaders.CompanyID = OrdersDetails.CompanyID AND OrdersHeaders.OrderYear = OrdersDetails.OrderYear AND OrdersHeaders.OrderNo = OrdersDetails.OrderNo INNER JOIN
							 TransactionsPromotions ON OrdersHeaders.CompanyID = TransactionsPromotions.CompanyID AND OrdersHeaders.OrderYear = TransactionsPromotions.TrYear AND 
							 OrdersHeaders.OrderNo = TransactionsPromotions.TrNo RIGHT OUTER JOIN
							 SalesPersonItemBonusTarget ON OrdersDetails.CompanyID = SalesPersonItemBonusTarget.CompanyID AND OrdersDetails.OrderYear = SalesPersonItemBonusTarget.TargetYear AND 
							 OrdersDetails.ItemCode = SalesPersonItemBonusTarget.ItemCode AND OrdersDetails.UnitID = SalesPersonItemBonusTarget.UnitID AND OrdersHeaders.SalesPersonID = @SalesmanNo AND 
							 OrdersHeaders.OrderYear = YEAR(@SendDate) AND MONTH(OrdersHeaders.OrderDate) = MONTH(@SendDate)
							 AND TransactionsPromotions.InputItem = '' AND (TransactionsPromotions.TrTypeID = 3) AND (TransactionsPromotions.IncludeInTargetBonus = 1)
							 AND (ISNULL(OrdersHeaders.IsVoid,0) = 0) AND (ISNULL(OrdersHeaders.Approved,0) = 1)
	WHERE        (SalesPersonItemBonusTarget.CompanyID = @CompNo) AND (SalesPersonItemBonusTarget.SalesPersonID = @SalesmanNo) AND (SalesPersonItemBonusTarget.TargetYear = YEAR(@SendDate)) AND 
							 (CASE WHEN Month(@SendDate) BETWEEN 1 AND 6 THEN CASE WHEN Month(@SendDate) = 1 THEN SalesPersonItemBonusTarget.M1 ELSE CASE WHEN Month(@SendDate) 
							 = 2 THEN SalesPersonItemBonusTarget.M2 ELSE CASE WHEN Month(@SendDate) = 3 THEN SalesPersonItemBonusTarget.M3 ELSE CASE WHEN Month(@SendDate) 
							 = 4 THEN SalesPersonItemBonusTarget.M4 ELSE CASE WHEN Month(@SendDate) = 5 THEN SalesPersonItemBonusTarget.M5 ELSE CASE WHEN Month(@SendDate) 
							 = 6 THEN SalesPersonItemBonusTarget.M6 END END END END END END ELSE CASE WHEN Month(@SendDate) = 7 THEN SalesPersonItemBonusTarget.M7 ELSE CASE WHEN Month(@SendDate) 
							 = 8 THEN SalesPersonItemBonusTarget.M8 ELSE CASE WHEN Month(@SendDate) = 9 THEN SalesPersonItemBonusTarget.M9 ELSE CASE WHEN Month(@SendDate) 
							 = 10 THEN SalesPersonItemBonusTarget.M10 ELSE CASE WHEN Month(@SendDate) = 11 THEN SalesPersonItemBonusTarget.M11 ELSE CASE WHEN Month(@SendDate) 
							 = 12 THEN SalesPersonItemBonusTarget.M12 END END END END END END END > 0)
	GROUP BY SalesPersonItemBonusTarget.CompanyID, SalesPersonItemBonusTarget.SalesPersonID, SalesPersonItemBonusTarget.TargetYear, SalesPersonItemBonusTarget.ItemCode, SalesPersonItemBonusTarget.UnitID,
							  SalesPersonItemBonusTarget.M1, SalesPersonItemBonusTarget.M2, SalesPersonItemBonusTarget.M3, SalesPersonItemBonusTarget.M4, SalesPersonItemBonusTarget.M5, SalesPersonItemBonusTarget.M6, 
							 SalesPersonItemBonusTarget.M7, SalesPersonItemBonusTarget.M8, SalesPersonItemBonusTarget.M9, SalesPersonItemBonusTarget.M10, SalesPersonItemBonusTarget.M11, SalesPersonItemBonusTarget.M12
) as xtbl
Group By CompanyID, SalesPersonID, TargetYear, TargetMonth, ItemCode, UnitID, MaxQty
*/
END

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_SalesmanItemBonusTarget [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')


Skip_BONUSTARGET:

IF @ClientActive = 27 OR @ClientActive = 30 OR @ClientActive = 118 or @ClientActive = 136 or @ClientActive =146 Or @ClientActive = 50 Or @ClientActive= 41 or @ClientActive=82
BEGIN
	goto Skip_QtyLimit
END


--///////////  SalesmanGroupItem QtyLimit //////////////////////////////////////////////

SET @BeginTime = Convert(varchar(20),GetDate(),108)
 
	--DECLARE @UseItemBonusTargetSalesmanGroup varchar(50)=dbo.Fun_GetSalesmanSysOpValue(@CompNo,@SalesmanNo,427)
	--DECLARE @UseItemBonusTargetGroup bit=0
	--SELECT        @UseItemBonusTargetGroup=ISNULL(UseItemBonusTargetGroup,0)
	--FROM            CompanyParameters
	--WHERE        (CompanyID = @CompNo)
	 
	--DELETE FROM [OSFA_DB].[dbo].[OT_SalesmanItemBonusTarget] WHERE(CompNo = @CompNo) AND (SalesmanNo = @SalesmanGroupID)



		DELETE FROM [OSFA_DB].[dbo].OT_SalesmanGroupItemQtyLimit WHERE(CompanyID = @CompNo) AND (SalesmanNo = @SalesmanNo)
	

		INSERT INTO OSFA_DB.dbo.OT_SalesmanGroupItemQtyLimit (CompanyID, SalesmanNo, [SalesPersonGroupID], [ItemsTargetGroup], [SoldQtyLimit], [SoldQty])		 
		SELECT DISTINCT 
								 @CompNo AS Expr1, @SalesmanNo AS Expr2, Fun_GetInvoiceAndOrderForSoldQtyLimit_1.SalesPersonsGroupID, Fun_GetInvoiceAndOrderForSoldQtyLimit_1.ItemGroup, dbo.GetItemSmallUnitQty(@CompNo, Items.ItemCode, 
								 SalesPersonGroupItemQtyLimit.UnitID, SalesPersonGroupItemQtyLimit.SoldQtyLimit) AS Expr3, Fun_GetInvoiceAndOrderForSoldQtyLimit_1.SoldQty
		FROM            Items INNER JOIN
								 SalesPersonGroupItemQtyLimit ON Items.CompanyID = SalesPersonGroupItemQtyLimit.CompanyID AND Items.ItemBonusTargetGroupID = SalesPersonGroupItemQtyLimit.ItemsTargetGroup LEFT OUTER JOIN
								 dbo.Fun_GetInvoiceAndOrderForSoldQtyLimit(@CompNo, YEAR(@SendDate), @SalesmanNo, @SalesmanNo, '0', 'zzzzzzzzzzzzzz', @SalesmanGroupID, @SalesmanGroupID) AS Fun_GetInvoiceAndOrderForSoldQtyLimit_1 ON
								  SalesPersonGroupItemQtyLimit.CompanyID = Fun_GetInvoiceAndOrderForSoldQtyLimit_1.CompanyID AND 
								 SalesPersonGroupItemQtyLimit.SalesPersonGroupID = Fun_GetInvoiceAndOrderForSoldQtyLimit_1.SalesPersonsGroupID AND 
								 SalesPersonGroupItemQtyLimit.ItemsTargetGroup = Fun_GetInvoiceAndOrderForSoldQtyLimit_1.ItemGroup
		WHERE Fun_GetInvoiceAndOrderForSoldQtyLimit_1.SalesPersonsGroupID IS NOT NULL  
		 
 

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_SalesmanGroupItemQtyLimit [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')







--///////////  CustomersItem Qty Limit //////////////////////////////////////////////

SET @BeginTime = Convert(varchar(20),GetDate(),108)
  
		DELETE FROM [OSFA_DB].[dbo].OT_CustomersItemQtyLimit WHERE(CompanyID = @CompNo) AND (SalesmanNo = @SalesmanNo)
	

		INSERT INTO OSFA_DB.dbo.OT_CustomersItemQtyLimit (CompanyID, SalesmanNo, CustomerID, ItemCode, [SoldQtyLimit], [SoldQty])		 
		SELECT DISTINCT 
								 @CompNo AS Expr1, @SalesmanNo AS Expr2, CustomersItemQtyLimit.CustomerID, CustomersItemQtyLimit.ItemCode, dbo.GetItemSmallUnitQty(@CompNo, Items.ItemCode, 
								 CustomersItemQtyLimit.UnitID, CustomersItemQtyLimit.SoldQtyLimit) AS Expr3, ISNULL(Fun_GetInvoiceAndOrderForSoldQtyLimit_ByCustomer_1.SoldQty,0)
		FROM            Items INNER JOIN
								 CustomersItemQtyLimit ON Items.CompanyID = CustomersItemQtyLimit.CompanyID AND Items.ItemCode = CustomersItemQtyLimit.ItemCode LEFT OUTER JOIN
								 dbo.[Fun_GetInvoiceAndOrderForSoldQtyLimit_ByCustomer](@CompNo, @SendDate) AS Fun_GetInvoiceAndOrderForSoldQtyLimit_ByCustomer_1 ON
								  CustomersItemQtyLimit.CompanyID = Fun_GetInvoiceAndOrderForSoldQtyLimit_ByCustomer_1.CompanyID AND 

								 CustomersItemQtyLimit.CustomerID = Fun_GetInvoiceAndOrderForSoldQtyLimit_ByCustomer_1.CustomerID AND 
								 CustomersItemQtyLimit.ItemCode = Fun_GetInvoiceAndOrderForSoldQtyLimit_ByCustomer_1.ItemCode INNER JOIN  
						OSFA_DB.dbo.OT_ItemsMF ON CustomersItemQtyLimit.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND CustomersItemQtyLimit.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo  INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON CustomersItemQtyLimit.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 CustomersItemQtyLimit.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo 
		WHERE          (CustomersItemQtyLimit.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

		 
 

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_CustomersItemQtyLimit [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')




--///////////  Customers Return Item Qty Limit //////////////////////////////////////////////

SET @BeginTime = Convert(varchar(20),GetDate(),108)
  
		DELETE FROM [OSFA_DB].[dbo].OT_CustomersReturnItemQtyLimit WHERE(CompanyID = @CompNo) AND (SalesmanNo = @SalesmanNo)
	

		INSERT INTO OSFA_DB.dbo.OT_CustomersReturnItemQtyLimit (CompanyID, SalesmanNo, CustomerID, ItemCode, ReturnQtyLimit, ReturnedQty)		 
		SELECT DISTINCT 
								 @CompNo AS Expr1, @SalesmanNo AS Expr2, CustomersReturnItemQtyLimit.CustomerID, CustomersReturnItemQtyLimit.ItemCode, dbo.GetItemSmallUnitQty(@CompNo, Items.ItemCode, 
								 CustomersReturnItemQtyLimit.UnitID, CustomersReturnItemQtyLimit.ReturnQtyLimit) AS Expr3, ISNULL(CustomersReturnItemQtyLimit.ReturnedQty,0)
		FROM            Items INNER JOIN
								 CustomersReturnItemQtyLimit ON Items.CompanyID = CustomersReturnItemQtyLimit.CompanyID AND Items.ItemCode = CustomersReturnItemQtyLimit.ItemCode   INNER JOIN  
						OSFA_DB.dbo.OT_ItemsMF ON CustomersReturnItemQtyLimit.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND CustomersReturnItemQtyLimit.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo  INNER JOIN
							 OSFA_DB.dbo.OT_CustomerMF ON CustomersReturnItemQtyLimit.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
							 CustomersReturnItemQtyLimit.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo 
		WHERE          (CustomersReturnItemQtyLimit.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

		 
 

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_CustomersReturnItemQtyLimit [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')




Skip_QtyLimit:

SET @BeginTime = Convert(varchar(20),GetDate(),108)

--////////// Target Info ////////////////////////////////////////////////////////////
Declare @SalesTarget float
Declare @SalesAmuont float
Declare @CollectionTarget float
Declare @CollectionAmuont float
Declare @DamageAmount float
Declare @CustomerSalesCount int
DECLARE @CountOfAllCustomers int
Declare @TotalWorkWithCustomer float

if @ClientActive = 30 or @ClientActive=118 or @ClientActive=68 or @ClientActive = 136 or @ClientActive =146 or @ClientActive=67 Or @ClientActive = 50
BEGIN
	goto Skip_Target
END
--==================================================

IF @ClientActive = 16
BEGIN
	SELECT        @SalesTarget = SUM(SalesPersonTargetsDetails.Amount) 
	FROM            SalesPersonTargets INNER JOIN
							 dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON SalesPersonTargets.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
							 SalesPersonTargets.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID INNER JOIN
							 SalesPersonTargetsDetails ON SalesPersonTargets.CompanyID = SalesPersonTargetsDetails.CompanyID AND SalesPersonTargets.SalesPersonID = SalesPersonTargetsDetails.SalesPersonID AND 
							 SalesPersonTargets.TargetYear = SalesPersonTargetsDetails.TargetYear AND SalesPersonTargets.TargetMonth = SalesPersonTargetsDetails.TargetMonth
	WHERE        (SalesPersonTargets.CompanyID = @CompNo) AND (SalesPersonTargets.SalesPersonID = @SalesmanNo OR
							 SalesPersonTargets.SalesPersonID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE SalesPersonTargets.SalesPersonID END) AND (SalesPersonTargets.TargetYear = YEAR(@SendDate)) AND 
							 (SalesPersonTargets.TargetMonth = MONTH(@SendDate)) AND (SalesPersonTargetsDetails.TargetReferenceID = 2)
END


ELSE if @ClientActive=21
BEGIN
select  @SalesTarget =sum(round(SalesTarget,3)) from (
	SELECT       
	 case when DaysNumber =0 then SUM(SalesPersonTargets.Amount) else SUM(SalesPersonTargets.Amount /DaysNumber) end as SalesTarget
	FROM            SalesPersonTargets INNER JOIN
							 dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON SalesPersonTargets.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
							 SalesPersonTargets.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
	WHERE        (SalesPersonTargets.CompanyID = @CompNo) 
				AND (SalesPersonTargets.SalesPersonID = @SalesmanNo OR SalesPersonTargets.SalesPersonID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE SalesPersonTargets.SalesPersonID END) 
				AND (SalesPersonTargets.TargetYear = YEAR(@SendDate)) 
				AND (SalesPersonTargets.TargetMonth = MONTH(@SendDate))
				group by SalesPersonTargets.DaysNumber ) as xbt
END

ELSE if @ClientActive = 165 and @CompNo=1
BEGIN
	
	SELECT        @SalesTarget = SUM(SalesPersonTargets.Amount)
	FROM            SalesPersonTargets INNER JOIN
							 dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON SalesPersonTargets.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
							 SalesPersonTargets.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
	WHERE        (SalesPersonTargets.CompanyID = @CompNo) 
				AND (SalesPersonTargets.SalesPersonID = @SalesmanNo OR SalesPersonTargets.SalesPersonID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE SalesPersonTargets.SalesPersonID END) 
				AND (SalesPersonTargets.TargetYear = YEAR(@SendDate)) 
				--AND (SalesPersonTargets.TargetMonth = MONTH(@SendDate))
END
ELSE
BEGIN
	
	SELECT        @SalesTarget = SUM(SalesPersonTargets.Amount)
	FROM            SalesPersonTargets INNER JOIN
							 dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON SalesPersonTargets.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
							 SalesPersonTargets.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
	WHERE        (SalesPersonTargets.CompanyID = @CompNo) 
				AND (SalesPersonTargets.SalesPersonID = @SalesmanNo OR SalesPersonTargets.SalesPersonID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE SalesPersonTargets.SalesPersonID END) 
				AND (SalesPersonTargets.TargetYear = YEAR(@SendDate)) 
				AND (SalesPersonTargets.TargetMonth = MONTH(@SendDate))
END




--==================================================

SELECT        @CollectionTarget = SUM(SalesPersonCollectionsTargets.Amount) 
FROM            SalesPersonCollectionsTargets INNER JOIN
                         dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON SalesPersonCollectionsTargets.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
                         SalesPersonCollectionsTargets.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
WHERE        (SalesPersonCollectionsTargets.CompanyID = @CompNo) 
				AND (SalesPersonCollectionsTargets.SalesPersonID = @SalesmanNo OR SalesPersonCollectionsTargets.SalesPersonID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE SalesPersonCollectionsTargets.SalesPersonID END) 
				AND (SalesPersonCollectionsTargets.TargetYear = YEAR(@SendDate)) 
				AND (SalesPersonCollectionsTargets.TargetMonth = MONTH(@SendDate))

--==================================================

IF @ClientActive = 16
BEGIN
	SELECT       @SalesAmuont =  ROUND(SUM(DB.dbo.InvDailyDF.NetSellValue),3) * - 1
	FROM            DB.dbo.InvDailyDF INNER JOIN
		                     DB.dbo.InvDailyHF ON DB.dbo.InvDailyDF.CompNo = DB.dbo.InvDailyHF.CompNo AND DB.dbo.InvDailyDF.VouYear = DB.dbo.InvDailyHF.VouYear AND DB.dbo.InvDailyDF.VouType = DB.dbo.InvDailyHF.VouType AND 
			                 DB.dbo.InvDailyDF.VouNo = DB.dbo.InvDailyHF.VouNo INNER JOIN
				             DB.dbo.InvItemsMF ON DB.dbo.InvDailyDF.CompNo = DB.dbo.InvItemsMF.CompNo AND DB.dbo.InvDailyDF.ItemNo = DB.dbo.InvItemsMF.ItemNo
	WHERE        (DB.dbo.InvDailyDF.CompNo = @CompNo) AND (DB.dbo.InvDailyDF.VouYear = YEAR(@SendDate)) AND (MONTH(DB.dbo.InvDailyDF.VouDate) = MONTH(@SendDate)) AND (DB.dbo.InvDailyDF.VouType IN (9)) AND 
		                     (DB.dbo.InvDailyHF.SalseMan = @SalesmanNo) AND (DB.dbo.InvItemsMF.Categ = 'F')
END
ELSE if @ClientActive = 69
BEGIN
	SELECT         @SalesAmuont = ROUND(SUM(TransactionsDetails.Price - ISNULL (TransactionsDetails.DiscountAmount,0) - ISNULL(TransactionsDetails.VoucherDiscount,0) - ISNULL(TransactionsDetails.CustomerDiscountAmount,0)), 3) 
	FROM            TransactionsDetails INNER JOIN
							 TransactionsHeaders ON TransactionsDetails.CompanyID = TransactionsHeaders.CompanyID AND TransactionsDetails.TransactionTypeID = TransactionsHeaders.TransactionTypeID AND 
							 TransactionsDetails.TransactionYear = TransactionsHeaders.TransactionYear AND TransactionsDetails.TransactionNo = TransactionsHeaders.TransactionNo INNER JOIN
							 dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON TransactionsHeaders.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
							 TransactionsHeaders.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
	WHERE        (TransactionsDetails.CompanyID = @CompNo) 
					AND (TransactionsDetails.TransactionTypeID IN (1)) 
					AND (TransactionsDetails.TransactionYear = YEAR(@SendDate))
					AND (MONTH(TransactionsHeaders.TransactionDate) = MONTH(@SendDate))
					AND (TransactionsHeaders.SalesPersonID = @SalesmanNo OR TransactionsHeaders.SalesPersonID =  TransactionsHeaders.SalesPersonID ) 
END
ELSE if @ClientActive = 91
BEGIN
	SELECT         @SalesAmuont = ROUND(SUM(OrdersDetails.Price - OrdersDetails.DiscountAmount - OrdersDetails.VoucherDiscount - OrdersDetails.CustomerDiscountAmount), 3) 
	FROM            OrdersDetails INNER JOIN
							 OrdersHeaders ON OrdersDetails.CompanyID = OrdersHeaders.CompanyID AND 
							 OrdersDetails.OrderYear = OrdersHeaders.OrderYear AND OrdersDetails.OrderNo = OrdersHeaders.OrderNo INNER JOIN
							 dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON OrdersHeaders.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
							 OrdersHeaders.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
	WHERE        (OrdersDetails.CompanyID = @CompNo) 
					AND (OrdersDetails.OrderYear = YEAR(@SendDate))
					AND (MONTH(OrdersHeaders.OrderDate) = MONTH(@SendDate))
					AND (OrdersHeaders.SalesPersonID = @SalesmanNo)
					end

else if @ClientActive=13
begin

Declare @returnAmount float
	SELECT         @SalesAmuont = ROUND(SUM(TransactionsDetails.Price -TransactionsDetails.DiscountAmount - TransactionsDetails.VoucherDiscount-
	TransactionsDetails.CustomerDiscountAmount-(TransactionsDetails.TaxAmount)), 3) * - 1
	FROM            TransactionsDetails INNER JOIN
							 TransactionsHeaders ON TransactionsDetails.CompanyID = TransactionsHeaders.CompanyID AND TransactionsDetails.TransactionTypeID = TransactionsHeaders.TransactionTypeID AND 
							 TransactionsDetails.TransactionYear = TransactionsHeaders.TransactionYear AND TransactionsDetails.TransactionNo = TransactionsHeaders.TransactionNo INNER JOIN
							 dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON TransactionsHeaders.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
							 TransactionsHeaders.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
	WHERE        (TransactionsDetails.CompanyID = @CompNo) 
					AND (TransactionsDetails.TransactionTypeID IN (1)) 
					AND (TransactionsDetails.TransactionYear = YEAR(@SendDate))
					AND (MONTH(TransactionsHeaders.TransactionDate) = MONTH(@SendDate))
					AND (TransactionsHeaders.SalesPersonID = @SalesmanNo OR TransactionsHeaders.SalesPersonID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE TransactionsHeaders.SalesPersonID END) 


						SELECT         @returnAmount = ROUND(SUM(TransactionsDetails.Price -TransactionsDetails.DiscountAmount - TransactionsDetails.VoucherDiscount-
	TransactionsDetails.CustomerDiscountAmount-(TransactionsDetails.TaxAmount)), 3) * - 1
	FROM            TransactionsDetails INNER JOIN
							 TransactionsHeaders ON TransactionsDetails.CompanyID = TransactionsHeaders.CompanyID AND TransactionsDetails.TransactionTypeID = TransactionsHeaders.TransactionTypeID AND 
							 TransactionsDetails.TransactionYear = TransactionsHeaders.TransactionYear AND TransactionsDetails.TransactionNo = TransactionsHeaders.TransactionNo INNER JOIN
							 dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON TransactionsHeaders.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
							 TransactionsHeaders.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
	WHERE        (TransactionsDetails.CompanyID = @CompNo) 
					AND (TransactionsDetails.TransactionTypeID IN (2)) 
					AND (TransactionsDetails.TransactionYear = YEAR(@SendDate))
					AND (MONTH(TransactionsHeaders.TransactionDate) = MONTH(@SendDate))
					AND (TransactionsHeaders.SalesPersonID = @SalesmanNo OR TransactionsHeaders.SalesPersonID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE TransactionsHeaders.SalesPersonID END) 
					--Select @SalesAmuont as Salesamount
					--Select isNULL(@returnAmount,0) as Salesreturn
					
					select @SalesAmuont=@SalesAmuont-isNULL(@returnAmount,0) 
					--select @SalesAmuont as DIFF
END


else if @ClientActive=27
Begin

	SELECT       @SalesAmuont = ROUND(SUM(Olives_BO.dbo.InvoiceHistoryDF.SellValue - Olives_BO.dbo.InvoiceHistoryDF.DiscValue)
	,3) 
	FROM            Olives_BO.dbo.InvoiceHistoryDF INNER JOIN
                         Olives_BO.dbo.InvoiceHistoryHF ON Olives_BO.dbo.InvoiceHistoryDF.CompNo = Olives_BO.dbo.InvoiceHistoryHF.CompNo AND 
                         Olives_BO.dbo.InvoiceHistoryDF.VouType = Olives_BO.dbo.InvoiceHistoryHF.VouType AND 
                         Olives_BO.dbo.InvoiceHistoryDF.VouYear = Olives_BO.dbo.InvoiceHistoryHF.VouYear AND 
                         Olives_BO.dbo.InvoiceHistoryDF.VouNo = Olives_BO.dbo.InvoiceHistoryHF.VouNo INNER JOIN
                         Olives_BO.dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON Olives_BO.dbo.InvoiceHistoryHF.CompNo = Fun_GetSalesmanTreeByID_1.CompanyID AND 
                         Olives_BO.dbo.InvoiceHistoryHF.SalesmanNo = Fun_GetSalesmanTreeByID_1.ID
	WHERE        (Olives_BO.dbo.InvoiceHistoryDF.CompNo = @compno) AND (Olives_BO.dbo.InvoiceHistoryDF.VouType IN (1)) AND month (InvoiceHistoryHF.VouDate) = MONTH(@SendDate)
	             and year (InvoiceHistoryHF.VouDate) =year(@SendDate)

				 --Select @SalesAmuont SalesQS


	SELECT        @SalesTarget = SUM(SalesPersonTargets.Amount)
	FROM            SalesPersonTargets INNER JOIN
							 dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON SalesPersonTargets.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
							 SalesPersonTargets.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
	WHERE        (SalesPersonTargets.CompanyID = @CompNo) 
				AND (SalesPersonTargets.SalesPersonID = @SalesmanNo OR SalesPersonTargets.SalesPersonID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE SalesPersonTargets.SalesPersonID END) 
				AND (SalesPersonTargets.TargetYear = YEAR(@SendDate)) 
				AND (SalesPersonTargets.TargetMonth = MONTH(@SendDate))
				
				--Select @SalesTarget SalesQT
END
ELSE if @ClientActive =165 
BEGIN
If @CompNo=1
Begin
	SELECT         @SalesAmuont =Round(SUM(TransactionsDetails.Price - ISNULL(TransactionsDetails.DiscountAmount,0) - ISNULL(TransactionsDetails.VoucherDiscount,0) - ISNULL(TransactionsDetails.TaxAmount,0)  - ISNULL(TransactionsDetails.CustomerDiscountAmount, 0)) 
							 * - 1,3)
	FROM            TransactionsDetails INNER JOIN
							 TransactionsHeaders ON TransactionsDetails.CompanyID = TransactionsHeaders.CompanyID AND TransactionsDetails.TransactionTypeID = TransactionsHeaders.TransactionTypeID AND 
							 TransactionsDetails.TransactionYear = TransactionsHeaders.TransactionYear AND TransactionsDetails.TransactionNo = TransactionsHeaders.TransactionNo INNER JOIN
							 dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON TransactionsHeaders.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
							 TransactionsHeaders.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
	WHERE        (TransactionsDetails.CompanyID = @CompNo) 
					AND (TransactionsDetails.TransactionTypeID IN (1,2)) 
					AND (TransactionsDetails.TransactionYear = YEAR(@SendDate))
					--AND (MONTH(TransactionsHeaders.TransactionDate) = MONTH(@SendDate))
					AND (TransactionsHeaders.SalesPersonID = @SalesmanNo OR TransactionsHeaders.SalesPersonID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE TransactionsHeaders.SalesPersonID END) 
END
else

BEGIN
	SELECT         @SalesAmuont = Round(SUM(TransactionsDetails.Price - ISNULL(TransactionsDetails.DiscountAmount,0) - ISNULL(TransactionsDetails.VoucherDiscount,0) - ISNULL(TransactionsDetails.TaxAmount,0)  - ISNULL(TransactionsDetails.CustomerDiscountAmount, 0)) 
							 * - 1,3) 
							 FROM            TransactionsDetails INNER JOIN
							 TransactionsHeaders ON TransactionsDetails.CompanyID = TransactionsHeaders.CompanyID AND TransactionsDetails.TransactionTypeID = TransactionsHeaders.TransactionTypeID AND 
							 TransactionsDetails.TransactionYear = TransactionsHeaders.TransactionYear AND TransactionsDetails.TransactionNo = TransactionsHeaders.TransactionNo INNER JOIN
							 dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON TransactionsHeaders.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
							 TransactionsHeaders.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
	WHERE        (TransactionsDetails.CompanyID = @CompNo) 
					AND (TransactionsDetails.TransactionTypeID IN (1,2)) 
					AND (TransactionsDetails.TransactionYear = YEAR(@SendDate))
					AND (MONTH(TransactionsHeaders.TransactionDate) = MONTH(@SendDate))
					AND (TransactionsHeaders.SalesPersonID = @SalesmanNo OR TransactionsHeaders.SalesPersonID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE TransactionsHeaders.SalesPersonID END) 
END

end


ELSE
BEGIN
	SELECT         @SalesAmuont = ROUND(SUM(TransactionsDetails.Price - TransactionsDetails.DiscountAmount - TransactionsDetails.VoucherDiscount - TransactionsDetails.CustomerDiscountAmount), 3) * - 1
	FROM            TransactionsDetails INNER JOIN
							 TransactionsHeaders ON TransactionsDetails.CompanyID = TransactionsHeaders.CompanyID AND TransactionsDetails.TransactionTypeID = TransactionsHeaders.TransactionTypeID AND 
							 TransactionsDetails.TransactionYear = TransactionsHeaders.TransactionYear AND TransactionsDetails.TransactionNo = TransactionsHeaders.TransactionNo INNER JOIN
							 dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON TransactionsHeaders.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
							 TransactionsHeaders.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
	WHERE        (TransactionsDetails.CompanyID = @CompNo) 
					AND (TransactionsDetails.TransactionTypeID IN (1)) 
					AND (TransactionsDetails.TransactionYear = YEAR(@SendDate))
					AND (MONTH(TransactionsHeaders.TransactionDate) = MONTH(@SendDate))
					AND (TransactionsHeaders.SalesPersonID = @SalesmanNo OR TransactionsHeaders.SalesPersonID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE TransactionsHeaders.SalesPersonID END) 
END
--==================================================
 
SELECT        @DamageAmount = ROUND(SUM(TransactionsDetails.Price - TransactionsDetails.DiscountAmount - TransactionsDetails.VoucherDiscount - TransactionsDetails.CustomerDiscountAmount), 3) 
FROM            TransactionsDetails INNER JOIN
                         TransactionsHeaders ON TransactionsDetails.CompanyID = TransactionsHeaders.CompanyID AND TransactionsDetails.TransactionTypeID = TransactionsHeaders.TransactionTypeID AND 
                         TransactionsDetails.TransactionYear = TransactionsHeaders.TransactionYear AND TransactionsDetails.TransactionNo = TransactionsHeaders.TransactionNo INNER JOIN
                         dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON TransactionsHeaders.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
                         TransactionsHeaders.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
WHERE        (TransactionsDetails.CompanyID = @CompNo) AND (TransactionsDetails.TransactionTypeID IN (2)) AND (TransactionsDetails.TransactionYear = YEAR(@SendDate)) AND 
                         (MONTH(TransactionsHeaders.TransactionDate) = MONTH(@SendDate))
						  AND (TransactionsHeaders.SalesPersonID = @SalesmanNo OR TransactionsHeaders.SalesPersonID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE TransactionsHeaders.SalesPersonID END)  
						  AND (TransactionsDetails.ItemStatus = 2)				 
--==================================================

SELECT        @CollectionAmuont = ROUND(SUM(Receipts.Amount), 3)
FROM            Receipts INNER JOIN
                         dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON Receipts.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
                         Receipts.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
WHERE        (Receipts.CompanyID = @CompNo) AND (Receipts.TransactionTypeID = 3) AND (Receipts.TransactionYear = YEAR(@SendDate)) 
				AND (Receipts.SalesPersonID = @SalesmanNo OR Receipts.SalesPersonID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE Receipts.SalesPersonID END)  
				AND (MONTH(Receipts.TransactionDate) = MONTH(@SendDate))

--==================================================

IF @ClientActive = 8 --Added By Eliwah
BEGIN
	declare @TRGfromDate date = cast(YEAR(@SendDate) as nvarchar(4)) + '-' + cast(MONTH(@SendDate) as nvarchar(2)) + '-01' 
	declare @TRGToDate date = cast(YEAR(@SendDate) as nvarchar(4)) + '-' + cast(MONTH(@SendDate) as nvarchar(2)) + '-' 
						+ case when @ToMonth = 2 then cast(28 as nvarchar(2)) when @ToMonth in(1,3,5,7,8,10,12) then cast(31 as nvarchar(2)) else cast(30 as nvarchar(2)) end

	SELECT        *
	into #Alpha_Inv
	FROM            DB.dbo.InvT_GeneralTransactions(@CompNo, 0, 999999, ' ', 'zzzzzzzzzzzzzzzzzzzz', @TRGfromDate, @TRGToDate, 4, 'sys') AS InvT_GeneralTransactions_1
	WHERE        (VouType IN (2, 9))
	--------------------------------
	SELECT        *
	into #Alpha_Voh
	FROM            DB.dbo.GlN_UnionVodVohTransDetls(@CompNo, 0, 999999, @TRGfromDate, @TRGToDate, 'Sys') AS GlN_UnionVodVohTransDetls_1
	WHERE        (voh_type = 1)


	SELECT        @SalesTarget = SUM(SalesPersonTargetsDetails.Amount)
	FROM            SalesPersonTargetsDetails INNER JOIN
							 dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON SalesPersonTargetsDetails.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
							 SalesPersonTargetsDetails.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
	WHERE        (SalesPersonTargetsDetails.CompanyID = @CompNo) 
				AND (SalesPersonTargetsDetails.SalesPersonID = @SalesmanNo OR SalesPersonTargetsDetails.SalesPersonID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE SalesPersonTargetsDetails.SalesPersonID END) 
				AND (SalesPersonTargetsDetails.TargetYear = YEAR(@SendDate)) 
				AND (SalesPersonTargetsDetails.TargetMonth = MONTH(@SendDate))
	

	SELECT			@SalesAmuont =  ROUND(SUM(#Alpha_Inv.Sell - isnull(#Alpha_Inv.VouDiscount,0) ),3) *-1
	FROM			#Alpha_Inv
	WHERE			#Alpha_Inv.CompNo = @CompNo and #Alpha_Inv.VouYear = YEAR(@SendDate) and MONTH(#Alpha_Inv.VouDate) = MONTH(@SendDate) and #Alpha_Inv.SalseMan = @SalesmanNo


	SELECT			@CollectionAmuont = ROUND(SUM(#Alpha_Voh.AmtCr),3)
	FROM			#Alpha_Voh
	WHERE			#Alpha_Voh.voh_comp = @CompNo AND YEAR(#Alpha_Voh.voh_date) = YEAR(@SendDate) AND MONTH(#Alpha_Voh.voh_date) = MONTH(@SendDate) AND #Alpha_Voh.Emp_Collect = @SalesmanNo


	DROP TABLE #Alpha_Inv
	DROP TABLE #Alpha_Voh
END

--==================================================
if @ClientActive = 19 -- ÇáãÇÓÉ ÇáÒÑÞÇÁ from alpha
BEGIN

-- the below is right in comment 
/*
SELECT	ROUND(ISNULL(AR_SManSaleSumTot.TotCashSale, 0) + ISNULL(AR_SManRecSumTot_1.TotalCash, 0) - ISNULL(AR_SManSaleSumTot.TotCashRetSale, 0),3) as SalesAmount
		FROM            DB.dbo.AR_SManRecSumTot(@CompNo, @SalesmanNo, @SalesmanNo, @FirstDayInMonthDate, @SendDate) AS AR_SManRecSumTot_1 RIGHT OUTER JOIN
								 DB.dbo.Salesman ON AR_SManRecSumTot_1.voh_comp = DB.dbo.Salesman.CompNo AND AR_SManRecSumTot_1.Emp_Collect = DB.dbo.Salesman.SalesmanNo LEFT OUTER JOIN
								 DB.dbo.AR_SManSaleSumTot(@CompNo, @SalesmanNo, SalesmanNo, @FirstDayInMonthDate, @SendDate, 'sys') AS AR_SManSaleSumTot ON 
								 DB.dbo.Salesman.CompNo = AR_SManSaleSumTot.CompNo AND DB.dbo.Salesman.SalesmanNo = AR_SManSaleSumTot.SManNo
		WHERE        (DB.dbo.Salesman.CompNo = @CompNo) AND (DB.dbo.Salesman.SalesmanNo = @SalesmanNo) 
*/
	SELECT  @SalesAmuont = SUM(SalesAmount)
	FROM(
		SELECT	ROUND(ISNULL(AR_SManSaleSumTot.TotCashSale, 0) + ISNULL(AR_SManRecSumTot_1.TotalCash, 0) - ISNULL(AR_SManSaleSumTot.TotCashRetSale, 0),3) as SalesAmount
		FROM            DB.dbo.AR_SManRecSumTot(@CompNo, 0, 999999999, @SalesmanNo, @SalesmanNo, @FirstDayInMonthDate, @SendDate) AS AR_SManRecSumTot_1 RIGHT OUTER JOIN
								 DB.dbo.Salesman ON AR_SManRecSumTot_1.voh_comp = DB.dbo.Salesman.CompNo AND AR_SManRecSumTot_1.Emp_Collect = DB.dbo.Salesman.SalesmanNo LEFT OUTER JOIN
								 DB.dbo.AR_SManSaleSumTot(@CompNo, 0, 999999999, @FirstDayInMonthDate, @SendDate, 'sys') AS AR_SManSaleSumTot ON 
								 DB.dbo.Salesman.CompNo = AR_SManSaleSumTot.CompNo AND DB.dbo.Salesman.SalesmanNo = AR_SManSaleSumTot.SManNo
		WHERE        (DB.dbo.Salesman.CompNo = @CompNo) AND (DB.dbo.Salesman.SalesmanNo = @SalesmanNo) 
		Union ALL
		SELECT SUM(voh_amount) * -1 
		FROM(
			SELECT     voh_amount       
			FROM         db.dbo.glvohmf
			WHERE     (voh_comp = @CompNo) AND (voh_type = 1) AND (voh_side = 0) AND (Emp_Collect = @SalesmanNo) AND
						(CodeDate BETWEEN YEAR(@FirstDayInMonthDate) * 10000 + MONTH(@FirstDayInMonthDate) 
								  * 100 + DAY(@FirstDayInMonthDate) AND YEAR(@SendDate) * 10000 + MONTH(@SendDate) * 100 + DAY(@SendDate))
								  AND voh_doctype = 9               
			union

			SELECT    vod_amount 
			FROM         db.dbo.glvodmf
			WHERE     (vod_comp = @CompNo) AND (vod_type = 1) AND (vod_side = 0) AND (Emp_Collect = @SalesmanNo) AND
						(CodeDate BETWEEN YEAR(@FirstDayInMonthDate) * 10000 + MONTH(@FirstDayInMonthDate) 
								  * 100 + DAY(@FirstDayInMonthDate) AND YEAR(@SendDate) * 10000 + MONTH(@SendDate) * 100 + DAY(@SendDate))
								  AND vod_doctype = 9
		) as Xtbl
	) as Ytbl
END

--==================================================

if @ClientActive= 20 
begin 

SELECT   @CustomerSalesCount =COUNT (DISTINCT LogActionTransaction.Data1)
FROM         dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 INNER JOIN
                      LogActionTransaction ON Fun_GetSalesmanTreeByID_1.CompanyID = LogActionTransaction.CompNo AND 
                      Fun_GetSalesmanTreeByID_1.ID = LogActionTransaction.SalesmanID
WHERE    (LogActionTransaction.ActionID = 0) AND  (MONTH(LogActionTransaction.TimeStamp) = MONTH(@SendDate)) AND (LogActionTransaction.SalesmanID = @SalesmanNo) AND 
                      (Fun_GetSalesmanTreeByID_1.CompanyID = @CompNo) AND (Year(LogActionTransaction.TimeStamp) = Year(@SendDate))
END                
ELSE 
begin
if @IsMakeOrder= 0
begin 

SELECT       @CustomerSalesCount = COUNT(DISTINCT TransactionsHeaders.CustomerID)
FROM            TransactionsHeaders INNER JOIN
                         dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON TransactionsHeaders.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
                         TransactionsHeaders.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
WHERE        (MONTH(TransactionsHeaders.TransactionDate) = MONTH(@SendDate)) 
				AND (TransactionsHeaders.SalesPersonID = @SalesmanNo OR TransactionsHeaders.SalesPersonID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE TransactionsHeaders.SalesPersonID END)   
				AND (TransactionsHeaders.CompanyID = @CompNo) AND 
                         (TransactionsHeaders.TransactionTypeID IN (1)) AND (TransactionsHeaders.TransactionYear = YEAR(@SendDate))
end                                                   
else 
begin
SELECT       @CustomerSalesCount = COUNT(DISTINCT ordersHeaders.CustomerID)
FROM            ordersHeaders INNER JOIN
                         dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON ordersHeaders.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
                         ordersHeaders.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
WHERE        (MONTH(ordersHeaders.OrderDate) = MONTH(@SendDate)) 
				AND (ordersHeaders.SalesPersonID = @SalesmanNo OR ordersHeaders.SalesPersonID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE ordersHeaders.SalesPersonID END)   
				AND (ordersHeaders.CompanyID = @CompNo)  
                          AND (ordersHeaders.OrderYear = YEAR(@SendDate))
end 
END

--==================================================

if @ClientActive= 16 
begin  

SELECT     @CountOfAllCustomers =COUNT(DISTINCT CustomersFinancialDetails.CustomerID) 
FROM         CustomersFinancialDetails INNER JOIN
                      SalesPersons ON CustomersFinancialDetails.CompanyID = SalesPersons.CompanyID AND 
                      CustomersFinancialDetails.PositionsID = SalesPersons.PositionID INNER JOIN
                      dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON 
                      SalesPersons.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND SalesPersons.ID = Fun_GetSalesmanTreeByID_1.ID INNER JOIN
                      Customers ON CustomersFinancialDetails.CompanyID = Customers.CompanyID AND CustomersFinancialDetails.CustomerID = Customers.ID
WHERE     (CustomersFinancialDetails.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo OR SalesPersons.ID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE SalesPersons.ID END) AND (ISNULL(Customers.IsSuspended,0) = 0)
						
				

END 

ELSE

Begin

SELECT        @CountOfAllCustomers = COUNT(DISTINCT CustomersFinancialDetails.CustomerID)
 FROM            CustomersFinancialDetails INNER JOIN
                         SalesPersons ON CustomersFinancialDetails.CompanyID = SalesPersons.CompanyID AND CustomersFinancialDetails.PositionsID = SalesPersons.PositionID INNER JOIN
                         dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON SalesPersons.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
                         SalesPersons.ID = Fun_GetSalesmanTreeByID_1.ID
WHERE        (CustomersFinancialDetails.CompanyID = @CompNo) 
				AND (SalesPersons.ID = @SalesmanNo OR SalesPersons.ID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE SalesPersons.ID END)   
END

--==================================================
Declare  @LogActionTransaction_Tmp TABLE (
	AutoID [numeric](30, 0) ,
	CompNo [smallint],
	ActionID [nvarchar](20) ,
	TimeStamp [datetime] ,
	SalesmanID [nvarchar](20),
	Data1 [nvarchar](100) ,
	Data2 [nvarchar](100) ,
	Data3 [nvarchar](max) ,
	Data4 [nvarchar](100) ,
	Data5 [nvarchar](100) ,
	GpsX [nchar](50) ,
	GpsY [nchar](50) ,
	RouteID [int] ,
	OSFA_AutoID [numeric](30, 0) ,
	PostedByEmail [bit],
	primary key(AutoID))

Insert into @LogActionTransaction_Tmp
SELECT        AutoID, CompNo, ActionID, TimeStamp, SalesmanID, Data1, Data2, Data3, Data4, Data5, GpsX, GpsY, RouteID, OSFA_AutoID, PostedByEmail
FROM            LogActionTransaction
WHERE        (CompNo = @CompNo) AND (SalesmanID = @SalesmanNo) AND (MONTH(TimeStamp) = MONTH(@SendDate)) AND (YEAR(TimeStamp) = YEAR(@SendDate))
and ActionID<> 49

declare @ActiveTimetbl table(EntryTime datetime, LeaveTime datetime)


Insert into @ActiveTimetbl
SELECT        CONVERT(Varchar(10),TimeStamp,108) as EntryTime,				
				(
				select top 1 CONVERT(Varchar(10),TimeStamp,108) from @LogActionTransaction_Tmp as i where i.CompNo = @CompNo
				AND (i.ActionID = N'3') AND J.Data1 = i.Data1 AND i.SalesmanID=@SalesmanNo				
				AND Month(TimeStamp) = Month(@SendDate)
				AND Year(TimeStamp) = Year(@SendDate)
				AND (i.TimeStamp >= J.TimeStamp)
				order by i.TimeStamp
				) AS LeaveTime
FROM            @LogActionTransaction_Tmp as J
WHERE        (CompNo = @CompNo) 
			    AND (ActionID = N'0') 
				AND (SalesmanID=@SalesmanNo) 				
				AND Month(TimeStamp) = Month(@SendDate)
				AND Year(TimeStamp) = Year(@SendDate)
ORDER BY CONVERT(Varchar(10),TimeStamp,108)

select @TotalWorkWithCustomer = cast(SUM(DATEDIFF(second,EntryTime,LeaveTime)) as float)/60/60
from @ActiveTimetbl



IF @ClientActive = 35

BEGIN


Declare @AllItemsCount int
Declare @AviItemsCount int 
Declare @TotalReturn float



select @AllItemsCount=COUNT (ItemCode) from Items 
where ISNULL (IsSuspended,0)=0 

/*

Remove the comment after update /* */ 2023-07-11

select @AviItemsCount=COUNT (*) from [LUX].[LUXintegratopn].dbo.vstock 
where LOCATION='001' and QTYONHAND >=60




SELECT @TotalReturn=  ISNULL (abs (SUM(X.invoice_amount)) ,0)
	FROM 
	(                                            
	SELECT customer_no, invoice_no, invoice_date, invoice_duedate, invoice_amount, invoice_remaining, invoice_nat, invoice_type, Company,
				(select Salesper from [LUX].[LUXintegratopn].dbo.vsales_history as i WHERE i.Company = j.Company and i.CUSTOMER = J.customer_no and i.TRANNUM = j.invoice_no) as SalesmanoNo
	FROM         [LUX].[LUXintegratopn].dbo.vCustomerTransaction as j
   	WHERE invoice_type IN ('cn', 'dn')
	) AS X 
	WHERE X.SalesmanoNo Collate SQL_Latin1_General_CP1256_CI_AS = (select Reference1 from SalesPersons Where CompanyID = 1 AND ID = @SalesmanNo)
	AND (CAST(SUBSTRING(CAST(X.invoice_date AS varchar), 1, 4) AS int) = YEAR (@senddate))  
	AND (CAST(SUBSTRING(CAST(X.invoice_date AS varchar), 5, 2) AS int) = MONTH (@senddate))



	SELECT     @SalesAmuont = SUM(vsales_target.transamount) , 
			   @SalesTarget = sum(CAST(vsales_target.targetamount as float))  
             --  @DamageAmount = SUM(vsales_target.damagedamount)
	FROM         [LUX].[LUXintegratopn].dbo.vsales_target vsales_target INNER JOIN
						  SalesPersons ON vsales_target.SALESPER = SalesPersons.Reference1 COLLATE Arabic_100_CI_AS_KS
	WHERE     (SalesPersons.CompanyID = @CompNo) and (PERIOD = MONTH(@SendDate)) and (YR = YEAR(@SendDate)) and (SalesPersons.ID = @SalesmanNo)
	and (CAST(vsales_target.targetamount as float))>0
	
	
	SELECT     @DamageAmount = SUM(vsales_target.damagedamount)
	FROM         [LUX].[LUXintegratopn].dbo.vsales_target vsales_target INNER JOIN
						  SalesPersons ON vsales_target.SALESPER = SalesPersons.Reference1 COLLATE Arabic_100_CI_AS_KS
	WHERE     (SalesPersons.CompanyID = @CompNo) and (PERIOD = MONTH(@SendDate)) and (YR = YEAR(@SendDate)) and (SalesPersons.ID = @SalesmanNo)
	--and (CAST(cds_integration.dbo.vsales_target.targetamount as float))>0
	
--	SELECT     @CollectionTarget = SUM(invoice_remaining) 
--FROM         (SELECT DISTINCT 
--                                              cds_integration.dbo.vCustomerTransaction.customer_no, cds_integration.dbo.vCustomerTransaction.invoice_no, 
--                                              cds_integration.dbo.vCustomerTransaction.invoice_amount, cds_integration.dbo.vCustomerTransaction.invoice_remaining, 
--                                              cds_integration.dbo.vCustomerTransaction.Company, cds_integration.dbo.vCustomerMaster2.cuma_ID
--                        FROM         cds_integration.dbo.vCustomerTransaction INNER JOIN
--                                              cds_integration.dbo.vCustomerMaster2 ON 
--                                              cds_integration.dbo.vCustomerTransaction.customer_no = cds_integration.dbo.vCustomerMaster2.cuma_ID INNER JOIN
--                                              SalesPersons ON cds_integration.dbo.vCustomerMaster2.cuma_SalesMan = SalesPersons.Reference1 COLLATE Arabic_100_CI_AS_KS
--                        WHERE     (cds_integration.dbo.vCustomerTransaction.invoice_remaining > 0) AND 
--                                              (CAST(SUBSTRING(CAST(cds_integration.dbo.vCustomerTransaction.invoice_duedate AS varchar), 1, 4) AS int) = YEAR('2017-05-10')) AND 
--                                              (CAST(SUBSTRING(CAST(cds_integration.dbo.vCustomerTransaction.invoice_duedate AS varchar), 5, 2) AS int) = MONTH('2017-05-10')) AND 
--                                              (cds_integration.dbo.vCustomerTransaction.invoice_type = 'INV'
--                                                AND (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo))) AS M
	
	--SELECT @CollectionTarget = SUM(X.invoice_remaining) 
	--FROM 
	--(                                            
	--SELECT customer_no, invoice_no, invoice_date, invoice_duedate, invoice_amount, invoice_remaining, invoice_nat, invoice_type, Company,
	--			(select Salesper from cds_integration.dbo.vsales_history as i WHERE i.Company = j.Company and i.CUSTOMER = J.customer_no and i.TRANNUM = j.invoice_no) as SalesmanoNo
	--FROM         cds_integration.dbo.vCustomerTransaction as j
	--WHERE J.invoice_type = 'INV' And J.invoice_remaining > 0
	--) AS X 
	--WHERE X.SalesmanoNo Collate SQL_Latin1_General_CP1256_CI_AS = (select Reference1 from SalesPersons Where CompanyID = @CompNo AND ID = @SalesmanNo)
	--AND (CAST(SUBSTRING(CAST(X.invoice_duedate AS varchar), 1, 4) AS int) <= YEAR(@SendDate))  
	--AND (CAST(SUBSTRING(CAST(X.invoice_duedate AS varchar), 5, 2) AS int) <= MONTH(@SendDate)) 


/*	declare @CollectionOldRemaning float 
declare @CollectionNewRemaning float 
declare @CollectionNewamount float
--declare @CollectionTarget float

SELECT @CollectionOldRemaning = SUM(X.invoice_remaining) 
	FROM 
	(                                            
	SELECT customer_no, invoice_no, invoice_date, invoice_duedate, invoice_amount, invoice_remaining, invoice_nat, invoice_type, Company,
				(select Salesper from cds_integration.dbo.vsales_history as i WHERE i.Company = j.Company and i.CUSTOMER = J.customer_no and i.TRANNUM = j.invoice_no) as SalesmanoNo
	FROM         cds_integration.dbo.vCustomerTransaction as j
	WHERE J.invoice_type in ('INV','DN','CN') And J.invoice_remaining > 0
	) AS X 
	WHERE X.SalesmanoNo Collate SQL_Latin1_General_CP1256_CI_AS = (select Reference1 from SalesPersons Where CompanyID = @CompNo AND ID = @salesmanNo)
	AND (CAST(SUBSTRING(CAST(X.invoice_duedate AS varchar), 1, 4) AS int) <= YEAR(@SendDate))  
	AND (CAST(SUBSTRING(CAST(X.invoice_duedate AS varchar), 5, 2) AS int) < MONTH(@SendDate)) 



	SELECT @CollectionNewamount = SUM(X.invoice_amount) 
	FROM 
	(                                            
	SELECT customer_no, invoice_no, invoice_date, invoice_duedate, invoice_amount, invoice_remaining, invoice_nat, invoice_type, Company,
				(select Salesper from cds_integration.dbo.vsales_history as i WHERE i.Company = j.Company and i.CUSTOMER = J.customer_no and i.TRANNUM = j.invoice_no) as SalesmanoNo
	FROM         cds_integration.dbo.vCustomerTransaction as j
	WHERE J.invoice_type in ('INV','DN','CN') And J.invoice_remaining > 0
	) AS X 
	WHERE X.SalesmanoNo Collate SQL_Latin1_General_CP1256_CI_AS = (select Reference1 from SalesPersons Where CompanyID =@CompNo  AND ID = @salesmanNo)
	AND (CAST(SUBSTRING(CAST(X.invoice_duedate AS varchar), 1, 4) AS int) <= YEAR(@SendDate))  
	AND (CAST(SUBSTRING(CAST(X.invoice_duedate AS varchar), 5, 2) AS int) = MONTH(@SendDate)) 


	SELECT @CollectionNEwRemaning = SUM(X.invoice_remaining) 
	FROM 
	(                                            
	SELECT customer_no, invoice_no, invoice_date, invoice_duedate, invoice_amount, invoice_remaining, invoice_nat, invoice_type, Company,
				(select Salesper from cds_integration.dbo.vsales_history as i WHERE i.Company = j.Company and i.CUSTOMER = J.customer_no and i.TRANNUM = j.invoice_no) as SalesmanoNo
	FROM         cds_integration.dbo.vCustomerTransaction as j
	WHERE J.invoice_type in ('INV','DN','CN') And J.invoice_remaining > 0
	) AS X 
	WHERE X.SalesmanoNo Collate SQL_Latin1_General_CP1256_CI_AS = (select Reference1 from SalesPersons Where CompanyID = @CompNo AND ID = @salesmanNo)
	AND (CAST(SUBSTRING(CAST(X.invoice_duedate AS varchar), 1, 4) AS int) <= YEAR(@SendDate))  
	AND (CAST(SUBSTRING(CAST(X.invoice_duedate AS varchar), 5, 2) AS int) <= MONTH(@SendDate)) 




set @CollectionTarget= @CollectionOldRemaning + @CollectionNewamount
set @CollectionAmuont=@CollectionTarget- @CollectionNewRemaning  
*/
	SELECT        @CollectionTarget = SUM(SalesPersonCollectionsTargets.Amount) 
FROM            SalesPersonCollectionsTargets INNER JOIN
                         dbo.Fun_GetSalesmanTreeByID(@CompNo, @SalesmanNo) AS Fun_GetSalesmanTreeByID_1 ON SalesPersonCollectionsTargets.CompanyID = Fun_GetSalesmanTreeByID_1.CompanyID AND 
                         SalesPersonCollectionsTargets.SalesPersonID = Fun_GetSalesmanTreeByID_1.ID
WHERE        (SalesPersonCollectionsTargets.CompanyID = @CompNo) 
				AND (SalesPersonCollectionsTargets.SalesPersonID = @SalesmanNo OR SalesPersonCollectionsTargets.SalesPersonID = CASE WHEN @ClientActive = 18 THEN @SalesmanNo ELSE SalesPersonCollectionsTargets.SalesPersonID END) 
				AND (SalesPersonCollectionsTargets.TargetYear = YEAR(@SendDate)) 
				AND (SalesPersonCollectionsTargets.TargetMonth = MONTH(@SendDate))


 select @CollectionAmuont= COUNT (CustomerRef1) from (
 
SELECT     CustomersMonthlyCollectionTarget.CompanyID, CustomersMonthlyCollectionTarget.TargetMonth, CustomersMonthlyCollectionTarget.TargetYear, 
                      CustomersMonthlyCollectionTarget.SalesmanID, CustomersMonthlyCollectionTarget.CustomerRef1, CustomersMonthlyCollectionTarget.CustomerRef2
FROM         CustomersMonthlyCollectionTarget INNER JOIN
                          (SELECT DISTINCT 
                                                   Receipts.CompanyID, Receipts.TransactionYear, MONTH(Receipts.TransactionDate) AS TrMonth, Receipts.SalesPersonID, Customers.Reference2, 
                                                   Customers.Barcode
                             FROM         Receipts INNER JOIN
                                                   Customers ON Receipts.CompanyID = Customers.CompanyID AND Receipts.CustomerID = Customers.ID) AS yy ON 
                      CustomersMonthlyCollectionTarget.CompanyID = yy.CompanyID AND CustomersMonthlyCollectionTarget.TargetYear = yy.TransactionYear AND 
                      CustomersMonthlyCollectionTarget.TargetMonth = yy.TrMonth AND  
                      CustomersMonthlyCollectionTarget.CustomerRef1 = yy.Barcode AND CustomersMonthlyCollectionTarget.CustomerRef2 = yy.Reference2
WHERE     (CustomersMonthlyCollectionTarget.CompanyID = @CompNo) AND (CustomersMonthlyCollectionTarget.TargetMonth = Month (@SendDate)) AND 
                      (CustomersMonthlyCollectionTarget.TargetYear = YEAR (@SendDate)) AND (CustomersMonthlyCollectionTarget.SalesmanID = @SalesmanNo)
                     ) XX



--select @CollectionAmuont =count(*) from (
	
--SELECT   distinct  XBT.Barcode, XBT.Reference2, XBT.monthCount, XBT.YearCount
--FROM         (SELECT DISTINCT 
--                                              Customers.Barcode, Customers.Reference2, MONTH(Receipts.TransactionDate) AS monthCount, YEAR(Receipts.TransactionDate) AS YearCount
--                        FROM         Receipts INNER JOIN
--                                              Customers ON Receipts.CompanyID = Customers.CompanyID AND Receipts.CustomerID = Customers.ID
--                        WHERE     (Receipts.TransactionTypeID = 3) AND (Receipts.CompanyID = @CompNo) AND (MONTH(Receipts.TransactionDate) = MONTH(@SendDate)) AND 
--                                              (YEAR(Receipts.TransactionDate) = YEAR(@SendDate))) AS XBT INNER JOIN
--                      CustomersMonthlyCollectionTarget ON XBT.Barcode = CustomersMonthlyCollectionTarget.CustomerRef1 AND 
--                      XBT.Reference2 = CustomersMonthlyCollectionTarget.CustomerRef2  and  SalesmanID=@SalesmanNo ) as Ata 



----- leatest 				
----select @CollectionAmuont =COUNT (*) from  (
----SELECT DISTINCT 
----                      Receipts.SalesPersonID, Customers.Barcode, Customers.Reference2, MONTH(Receipts.TransactionDate) AS monthCount, YEAR(Receipts.TransactionDate) 
----                      AS YearCount
----FROM         Receipts INNER JOIN
----                      Customers ON Receipts.CompanyID = Customers.CompanyID AND Receipts.CustomerID = Customers.ID INNER JOIN
----                      CustomersMonthlyCollectionTarget ON Customers.CompanyID = CustomersMonthlyCollectionTarget.CompanyID AND 
----                      Customers.Reference2 = CustomersMonthlyCollectionTarget.CustomerRef2 AND Customers.Barcode = CustomersMonthlyCollectionTarget.CustomerRef1 AND 
----                      Receipts.SalesPersonID = CustomersMonthlyCollectionTarget.SalesmanID
----WHERE     (Receipts.TransactionTypeID = 3) AND (Receipts.CompanyID = @CompNo) AND (Receipts.SalesPersonID = @SalesmanNo) AND (MONTH(Receipts.TransactionDate) 
----                      = MONTH( @SendDate) AND (YEAR(Receipts.TransactionDate) = YEAR ( @SendDate)))) as YBT	
	
	
--	select @CollectionAmuont= CustCount from 
--(
--SELECT    distinct  CompanyID, TransactionTypeID, SalesPersonID, COUNT(*) AS CustCount, month (TransactionDate) as monthCount,year  (TransactionDate)as YearCount 
--FROM         Receipts
--WHERE     (TransactionTypeID = 3) AND (CompanyID = @CompNo) and  month (TransactionDate)= month (@SendDate)   AND (CompanyID = @CompNo)
-- and  year  (TransactionDate)= year (@SendDate)
--GROUP BY CompanyID, TransactionTypeID, SalesPersonID,month (TransactionDate),year  (TransactionDate))
--as m 
	
	select @CustomerSalesCount =COUNT (*) from (
		SELECT DISTINCT 
                   vsales_history.CUSTOMER--, vsales_history.Company
	FROM         [LUX].[LUXintegratopn].dbo.vsales_history vsales_history INNER JOIN
                      SalesPersons ON vsales_history.SALESPER = SalesPersons.Reference1 COLLATE Arabic_100_CI_AS_KS
			WHERE    ( PERIOD = MONTH(@SendDate)) AND (YR =  YEAR(@SendDate)) AND (SalesPersons.ID = @SalesmanNo)) as CustomerSalesCount


	--SELECT @CustomerSalesCount = COUNT(*) 
	--FROM(
	--SELECT    Customers.ID as CustomerNo, Customers.Barcode, 
	--		ROW_NUMBER() over (partition by Customers.Barcode order by Customers.ID) as SerID		
	--FROM         cds_integration.dbo.vCustomerTransaction INNER JOIN
	--					  Customers ON cds_integration.dbo.vCustomerTransaction.customer_no = Customers.Barcode COLLATE Arabic_100_CI_AS_KS AND 
	--					  cds_integration.dbo.vCustomerTransaction.Company = Customers.Reference2 COLLATE SQL_Latin1_General_CP1_CI_AS INNER JOIN
	--					  CustomersFinancialDetails ON Customers.CompanyID = CustomersFinancialDetails.CompanyID AND 
	--					  Customers.ID = CustomersFinancialDetails.CustomerID INNER JOIN
	--					  SalesPersons ON CustomersFinancialDetails.CompanyID = SalesPersons.CompanyID AND CustomersFinancialDetails.PositionsID = SalesPersons.PositionID
	--WHERE  (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo)
	--AND cast(substring(cast(cds_integration.dbo.vCustomerTransaction.invoice_date as varchar),1,4) as int) = YEAR(@SendDate)
	--AND cast(substring(cast(cds_integration.dbo.vCustomerTransaction.invoice_date as varchar),5,2) as int) = Month(@SendDate)
	--) as Xtbl 
	--Where SerID = 1
	
	

	select @CountOfAllCustomers = Count (*)
		from (SELECT    distinct vCustomerMaster2.cuma_ID--,cuma_Company 
		FROM         [LUX].[LUXintegratopn].dbo.vCustomerMaster2 vCustomerMaster2 INNER JOIN
						  SalesPersons ON vCustomerMaster2.cuma_SalesMan = SalesPersons.Reference1 COLLATE Arabic_100_CI_AS_KS
		WHERE     (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo)) as COC
	
	
 
	*/
	END
	--SELECT   @CountOfAllCustomers = COUNT( cds_integration.dbo.vCustomerMaster2.cuma_ID) 
	--FROM         cds_integration.dbo.vCustomerMaster2 INNER JOIN
	--					  SalesPersons ON cds_integration.dbo.vCustomerMaster2.cuma_SalesMan = SalesPersons.Reference1 COLLATE Arabic_100_CI_AS_KS
	--WHERE     (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo)
	--SELECT     @CountOfAllCustomers = COUNT(DISTINCT CustomersFinancialDetails.CustomerID)
	--FROM         CustomersFinancialDetails INNER JOIN
	--					  SalesPersons ON CustomersFinancialDetails.CompanyID = SalesPersons.CompanyID AND CustomersFinancialDetails.PositionsID = SalesPersons.PositionID
	--WHERE     (SalesPersons.ID = @SalesmanNo) AND (SalesPersons.CompanyID = @CompNo)
	--GROUP BY SalesPersons.CompanyID

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Targets [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

Skip_Target:

--//////////////////// Coupons //////////////////////////////////
SET @BeginTime = Convert(varchar(20),GetDate(),108)

INSERT INTO OSFA_DB.[dbo].[OT_CouponsInfo]
           ([CompNo]
           ,[SalesmanNo]
           ,[ID]
           ,[BookNo]
           ,[CuoponNumber]
           ,[CustomerID]
           ,[CuoponBarcode]
           ,[PromotionID])
SELECT        CouponsBooksHeaders.CompanyID, OSFA_DB.dbo.OT_CustomerMF.SalesmanNo, CouponsBooksHeaders.ID, CouponsBooksHeaders.BookNo, CouponsBooksDetails.CuoponNumber, 
                         CouponsBooksHeaders.CustomerID, CouponsBooksDetails.CuoponBarcode, CouponsBooksDetails.PromotionID
FROM            CouponsBooksHeaders INNER JOIN
                         CouponsBooksDetails ON CouponsBooksHeaders.CompanyID = CouponsBooksDetails.CompanyID AND CouponsBooksHeaders.ID = CouponsBooksDetails.BookID INNER JOIN
                         OSFA_DB.dbo.OT_CustomerMF ON CouponsBooksHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND CouponsBooksHeaders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
WHERE        (CouponsBooksHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (CouponsBooksHeaders.IsSuspended = 0) AND (ISNULL(CouponsBooksDetails.IsUsed,0) = 0)

INSERT INTO OSFA_DB.[dbo].[OT_CouponsInfo]
           ([CompNo]
           ,[SalesmanNo]
           ,[ID]
           ,[BookNo]
           ,[CuoponNumber]
           ,[CustomerID]
           ,[CuoponBarcode]
           ,[PromotionID])
SELECT        CouponsBooksHeaders.CompanyID, OSFA_DB.dbo.OT_CustomerMF.SalesmanNo, CouponsBooksHeaders.ID, CouponsBooksHeaders.BookNo, CouponsBooksDetails.CuoponNumber, 
                         CouponsBooksDetails.CustomerID, CouponsBooksDetails.CuoponBarcode, CouponsBooksDetails.PromotionID
FROM            CouponsBooksHeaders INNER JOIN
                         CouponsBooksDetails ON CouponsBooksHeaders.CompanyID = CouponsBooksDetails.CompanyID AND CouponsBooksHeaders.ID = CouponsBooksDetails.BookID INNER JOIN
                         OSFA_DB.dbo.OT_CustomerMF ON CouponsBooksHeaders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND CouponsBooksDetails.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
WHERE        (CouponsBooksHeaders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (CouponsBooksHeaders.IsSuspended = 0) AND (ISNULL(CouponsBooksDetails.IsUsed,0) = 0)

--//// OT_SalesmanProcedures ////////////////////////////////////////////
If @ClientActive =38 
BEGIN
INSERT INTO OSFA_DB.dbo.OT_SalesmanProcedures (CompNo, SalesmanNo, CustomerNo, ProcedureID, ProcedureDate, ProcedureName)
SELECT        SalespersonsProcedures.CompanyID, SalesPersons.ID, SalespersonsProcedures.CustomerID, SalespersonsProcedures.ProcedureID, SalespersonsProcedures.ProcedureDate, DailyProcedures.Name
FROM            SalespersonsProcedures INNER JOIN
                         DailyProcedures ON SalespersonsProcedures.CompanyID = DailyProcedures.CompanyID AND SalespersonsProcedures.ProcedureID = DailyProcedures.ID INNER JOIN
                         SalesPersons ON SalespersonsProcedures.CompanyID = SalesPersons.CompanyID AND SalespersonsProcedures.PositionID = SalesPersons.PositionID
WHERE        (SalespersonsProcedures.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo) AND (ISNULL(SalespersonsProcedures.Status, 0) = 0) 
END
ELSE 
BEGIN
INSERT INTO OSFA_DB.dbo.OT_SalesmanProcedures (CompNo, SalesmanNo, CustomerNo, ProcedureID, ProcedureDate, ProcedureName)
SELECT        SalespersonsProcedures.CompanyID, SalesPersons.ID, SalespersonsProcedures.CustomerID, SalespersonsProcedures.ProcedureID, SalespersonsProcedures.ProcedureDate, DailyProcedures.Name
FROM            SalespersonsProcedures INNER JOIN
                         DailyProcedures ON SalespersonsProcedures.CompanyID = DailyProcedures.CompanyID AND SalespersonsProcedures.ProcedureID = DailyProcedures.ID INNER JOIN
                         SalesPersons ON SalespersonsProcedures.CompanyID = SalesPersons.CompanyID AND SalespersonsProcedures.PositionID = SalesPersons.PositionID
WHERE        (SalespersonsProcedures.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo) AND (ISNULL(SalespersonsProcedures.Status, 0) = 0) AND (SalespersonsProcedures.ProcedureDate >= @SendDate)
END

--////// OT_ProspectiveCustomer ///////////////////////////

INSERT INTO OSFA_DB.dbo.OT_ProspectiveCustomer
                         (CompNo, CustomerNo, SalesmanNo, ArName, EngName, PrNo, CustType, LocationID, CustomerBarcode, X_COORD, Y_COORD, TaxInclude, Tel, Email, CustomerRef1, CreditCash, ImageID, DiscountPerc, 
                         FullAddress)
SELECT        ProspectiveCustomers.CompanyID, ProspectiveCustomers.ID, @SalesmanNo AS Expr1, ProspectiveCustomers.Name, ISNULL(ProspectiveCustomers.ForeignName,''), ProspectiveCustomers.PriceListID, 
                         ProspectiveCustomers.TypeID, ProspectiveCustomers.LocationID, ISNULL(ProspectiveCustomers.Barcode,''), ProspectiveCustomers.Latitude, ProspectiveCustomers.Longitude, ProspectiveCustomers.TaxInclude, 
                         ProspectiveCustomers.TelephoneNo, ProspectiveCustomers.Email, ISNULL(ProspectiveCustomers.Reference1,''), ProspectiveCustomers.CreditCash, 
						 ROW_NUMBER() Over (order by ProspectiveCustomers.ID) AS ImageID, 0 AS Expr2, 
                         ProspectiveCustomers.Address
FROM            ProspectiveCustomers INNER JOIN
                         SalesPersons ON ProspectiveCustomers.CompanyID = SalesPersons.CompanyID AND ProspectiveCustomers.PositionsID = SalesPersons.PositionID
WHERE        (ProspectiveCustomers.CompanyID = @CompNo) AND (ProspectiveCustomers.PositionsID = @PositionsID) AND (SalesPersons.ID = @SalesmanNo)


--////// OT_LinkedSalesman ///////////////////////////
if @ClientActive=27
begin
delete from [OSFA_DB].[dbo].[OT_LinkedSalesman] where salesmanno=@SalesmanNo and Ref1 not in('100', '101','105')
End
IF @SalesPersonType in (0,1,2,3) AND @GroupCustByRelatedSalespersons=1
BEGIN
	WITH Cust_Link AS (  
		SELECT        OSFA_DB.dbo.OT_CustomerMF.CompNo, SalesPersons.ID AS SalesPersonsID, OSFA_DB.dbo.OT_CustomerMF.CustomerNo,OSFA_DB.dbo.OT_CustomerMF.SalesmanNo
											, ROW_NUMBER() OVER(PARTITION BY OSFA_DB.dbo.OT_CustomerMF.CustomerNo ORDER BY OSFA_DB.dbo.OT_CustomerMF.CustomerNo DESC) AS rk
		FROM            OSFA_DB.dbo.OT_CustomerMF INNER JOIN
								 CustomersFinancialDetails ON OSFA_DB.dbo.OT_CustomerMF.CompNo = CustomersFinancialDetails.CompanyID AND 
								 OSFA_DB.dbo.OT_CustomerMF.CustomerNo = CustomersFinancialDetails.CustomerID INNER JOIN
								 SalesPersons ON CustomersFinancialDetails.CompanyID = SalesPersons.CompanyID AND CustomersFinancialDetails.PositionsID = SalesPersons.PositionID
		WHERE        (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (CustomersFinancialDetails.PositionsID <> @PositionsID) AND (OSFA_DB.dbo.OT_CustomerMF.CompNo = @CompNo)
		 AND (CustomersFinancialDetails.PositionsID IN
										(SELECT        PositionID
										FROM            SalesPersons AS SalesPersons_1
										WHERE        (CompanyID = @CompNo) AND (Parent = @SalesmanNo)))
		   
	)
	UPDATE OSFA_DB.dbo.OT_CustomerMF SET OSFA_DB.dbo.OT_CustomerMF.LinkedSalesmanNo=Cust_Link.SalesPersonsID
	 FROM Cust_Link  INNER JOIN OSFA_DB.dbo.OT_CustomerMF AS CustMF ON
	 Cust_Link.CompNo=CustMF.CompNo AND
	 Cust_Link.CustomerNo=CustMF.CustomerNo AND
	 Cust_Link.SalesmanNo=CustMF.SalesmanNo
	 WHERE Cust_Link.rk=1
PRINT 'ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ'

if @ClientActive = 27
	 begin 
	 	INSERT INTO [OSFA_DB].[dbo].[OT_LinkedSalesman]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[LinkedSalesmanNo]
			   ,[ArName]
			   ,[EngName])
SELECT DISTINCT SalesPersons.CompanyID, OSFA_DB.dbo.OT_CustomerMF.SalesmanNo, SalesPersons.ID, SalesPersons.Name, SalesPersons.ForeignName
FROM            OSFA_DB.dbo.OT_CustomerMF INNER JOIN
                         SalesPersons ON OSFA_DB.dbo.OT_CustomerMF.CompNo = SalesPersons.CompanyID AND OSFA_DB.dbo.OT_CustomerMF.LinkedSalesmanNo = SalesPersons.ID LEFT OUTER JOIN
										 
                         OSFA_DB.dbo.OT_LinkedSalesman ON SalesPersons.CompanyID = OSFA_DB.dbo.OT_LinkedSalesman.CompNo AND SalesPersons.ID = OSFA_DB.dbo.OT_LinkedSalesman.SalesmanNo
WHERE        (SalesPersons.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) and OT_LinkedSalesman.CompNo IS NULL
and SalesPersons.ID not in (select distinct LinkedSalesmanNo from OSFA_DB.dbo.OT_LinkedSalesman where SalesmanNo=@SalesmanNo)																															  
	 end

else if @ClientActive=85-- and @GroupCustByRelatedSalespersons<>1
Begin


	IF @SalesPersonType in (3) --AND @GroupCustByRelatedSalespersons=1
	Begin

		INSERT INTO [OSFA_DB].[dbo].[OT_LinkedSalesman]
					   ([CompNo]
					   ,[SalesmanNo]
					   ,[LinkedSalesmanNo]
					   ,[ArName]
					   ,[EngName])
		select Distinct companyid,parent,ID ,name,Name from salespersons where  (Parent = @SalesmanNo) AND COMPANYID=@CompNo
	end 

	else
	Begin
		INSERT INTO [OSFA_DB].[dbo].[OT_LinkedSalesman]
					   ([CompNo]
					   ,[SalesmanNo]
					   ,[LinkedSalesmanNo]
					   ,[ArName]
					   ,[EngName])
		SELECT     DISTINCT   SalesPersons.CompanyID, OSFA_DB.dbo.OT_CustomerMF.SalesmanNo, SalesPersons.ID, SalesPersons.Name, SalesPersons.ForeignName
		FROM            OSFA_DB.dbo.OT_CustomerMF INNER JOIN
									SalesPersons ON OSFA_DB.dbo.OT_CustomerMF.CompNo = SalesPersons.CompanyID AND OSFA_DB.dbo.OT_CustomerMF.LinkedSalesmanNo = SalesPersons.ID
		WHERE        (SalesPersons.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
	End
END

else 
begin
	 
	INSERT INTO [OSFA_DB].[dbo].[OT_LinkedSalesman]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[LinkedSalesmanNo]
			   ,[ArName]
			   ,[EngName])

	SELECT     DISTINCT   SalesPersons.CompanyID, OSFA_DB.dbo.OT_CustomerMF.SalesmanNo, SalesPersons.ID, SalesPersons.Name, SalesPersons.ForeignName
	FROM            OSFA_DB.dbo.OT_CustomerMF INNER JOIN
							 SalesPersons ON OSFA_DB.dbo.OT_CustomerMF.CompNo = SalesPersons.CompanyID AND OSFA_DB.dbo.OT_CustomerMF.LinkedSalesmanNo = SalesPersons.ID
	WHERE        (SalesPersons.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)




END


END

if @ClientActive =93 or @ClientActive = 0  or @ClientActive=112
Begin
	INSERT INTO [OSFA_DB].[dbo].[OT_LinkedSalesman]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[LinkedSalesmanNo]
			   ,[ArName]
			   ,[EngName])

select @CompNo,@SalesmanNo,id,name,name from SalesPersons
where CompanyID=@CompNo
END

if @ClientActive = 111
begin
	INSERT INTO [OSFA_DB].[dbo].[OT_LinkedSalesman]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[LinkedSalesmanNo]
			   ,[ArName]
			   ,[EngName])

	SELECT     DISTINCT   SalesPersons.CompanyID, SalesPersons.ID, SalesPersons.ID, SalesPersons.Name, SalesPersons.ForeignName
	FROM          
							 SalesPersons 
	WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo)
end
 
   if @ClientActive=85-- and @GroupCustByRelatedSalespersons<>1
Begin


	IF @SalesPersonType in (2) --AND @GroupCustByRelatedSalespersons=1
	Begin
	Select '85 Product Manager'
	Delete from OSFA_DB..OT_LinkedSalesman where SalesmanNo=@SalesmanNo
	insert into [OSFA_DB].[dbo].[OT_LinkedSalesman] 
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[LinkedSalesmanNo]
			   ,[ArName]
			   ,[EngName])

SELECT        S.CompanyID, @salesmanno,S.ID, D.Name,D.name
FROM            dbo.Fun_GetSalesmanTreeByID(1, @SalesmanNo) as S 
inner join salespersons as d on s.CompanyID=d.CompanyID and S.ID=D.ID
where s.CompanyID=@CompNo

--SELECT        S.CompanyID, D.ID,S.ID, S.Name,S.name
--FROM            dbo.Fun_GetSalesmanTreeByID(1, 7043) as S 
--inner join salespersons as d on s.CompanyID=d.CompanyID 
--where s.CompanyID=1 and D.id=@SalesmanNo
END
else  IF @SalesPersonType in (3)
Begin
	Select '85 supervisor'
		INSERT INTO [OSFA_DB].[dbo].[OT_LinkedSalesman]
					   ([CompNo]
					   ,[SalesmanNo]
					   ,[LinkedSalesmanNo]
					   ,[ArName]
					   ,[EngName])
		select Distinct companyid,@SalesmanNo,ID ,name,Name from salespersons where  (ID = @SalesmanNo) AND COMPANYID=@CompNo
	

		INSERT INTO [OSFA_DB].[dbo].[OT_LinkedSalesman]
					   ([CompNo]
					   ,[SalesmanNo]
					   ,[LinkedSalesmanNo]
					   ,[ArName]
					   ,[EngName])
		select Distinct companyid,parent,ID ,name,Name from salespersons where  (Parent = @SalesmanNo) AND COMPANYID=@CompNo
	END

	else
	Begin
	Select '85 salesman'
		INSERT INTO [OSFA_DB].[dbo].[OT_LinkedSalesman]
					   ([CompNo]
					   ,[SalesmanNo]
					   ,[LinkedSalesmanNo]
					   ,[ArName]
					   ,[EngName])
		SELECT     DISTINCT   SalesPersons.CompanyID, OSFA_DB.dbo.OT_CustomerMF.SalesmanNo, SalesPersons.ID, SalesPersons.Name, SalesPersons.ForeignName
		FROM            OSFA_DB.dbo.OT_CustomerMF INNER JOIN
									SalesPersons ON OSFA_DB.dbo.OT_CustomerMF.CompNo = SalesPersons.CompanyID AND OSFA_DB.dbo.OT_CustomerMF.LinkedSalesmanNo = SalesPersons.ID
		WHERE        (SalesPersons.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)
	End
END



SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_CouponsInfo, OT_SalesmanProcedures, OT_ProspectiveCustomer, OT_LinkedSalesman [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')


SET @BeginTime = Convert(varchar(20),GetDate(),108)

IF @ClientActive = 49
BEGIN
--////// OT_ItemsPriceExceptions ///////////////////////////
INSERT INTO OSFA_DB.[dbo].[OT_ItemsPriceExceptions]
           ([CompNo]
           ,[SalesmanNo]
           ,[CustomerNo]
           ,[ItemNo]
           ,[UnitCode]
           ,[StartDate]
           ,[EndDate]
           ,[SellPrice]
           ,[TaxPerc]
           ,[TaxType]
           ,[DiscountPercent]
           ,[UseInReturn]
           ,[UseInSales]
           ,[SellPrice2]
           ,[SellPrice3]
           ,[Qty]
		   ,Tax_1_Type
		   ,Tax_1_Perc
		   ,Tax_2_Type
		   ,Tax_2_Perc)
SELECT CompanyID, SalesmanNo, CustomerID, ItemCode, UnitID, StartDate, EndDate, Price, Tax, TaxType, DiscountPercent, UseInReturn, UseInSales, SellPrice2, SellPrice2, Qty, TaxType1, Tax1, TaxType2, Tax2
FROM(
SELECT    ItemsPriceExceptions.CompanyID, OSFA_DB.dbo.OT_CustomerMF.SalesmanNo, ItemsPriceExceptions.CustomerID, ItemsPriceExceptions.ItemCode,  ItemsUnits.ID AS UnitID, ItemsPriceExceptions.StartDate,
                          ItemsPriceExceptions.EndDate, ItemsPriceExceptions.Price, ItemsPriceExceptions.Tax, ItemsPriceExceptions.TaxType, ItemsPriceExceptions.DiscountPercent, ItemsPriceExceptions.UseInReturn, 
                         ItemsPriceExceptions.UseInSales, ItemsPriceExceptions.SellPrice2, ItemsPriceExceptions.SellPrice3, ItemsPriceExceptions.Qty, ISNULL(ItemsPriceExceptions.TaxType1, 0) AS TaxType1, 
                         ISNULL(ItemsPriceExceptions.Tax1, 0) AS Tax1, ISNULL(ItemsPriceExceptions.TaxType2, 0) AS TaxType2, ISNULL(ItemsPriceExceptions.Tax2, 0) AS Tax2,
						 ROW_NUMBER () Over (Partition By ItemsPriceExceptions.CompanyID, OSFA_DB.dbo.OT_CustomerMF.SalesmanNo, ItemsPriceExceptions.CustomerID, ItemsPriceExceptions.ItemCode, ItemsUnits.ID
											 Order By ItemsPriceExceptions.CompanyID, OSFA_DB.dbo.OT_CustomerMF.SalesmanNo, ItemsPriceExceptions.CustomerID, ItemsPriceExceptions.ItemCode, ItemsUnits.ID, ItemsPriceExceptions.CreateDate Desc) AS RowID
FROM            ItemsPriceExceptions INNER JOIN
                         OSFA_DB.dbo.OT_CustomerMF ON ItemsPriceExceptions.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND ItemsPriceExceptions.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON ItemsPriceExceptions.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND ItemsPriceExceptions.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo INNER JOIN
                         ItemsUnits ON ItemsPriceExceptions.CompanyID = ItemsUnits.CompanyID AND ItemsPriceExceptions.UnitID = ItemsUnits.ID
WHERE        (ItemsPriceExceptions.CompanyID = @CompNo) 
			AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 
			AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, ItemsPriceExceptions.StartDate)) <= @SendDate) 
			AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, ItemsPriceExceptions.EndDate)) >= @SendDate) 
			AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
) AS Xtbl
WHERE RowID = 1
END
ELSE
BEGIN
--////// OT_ItemsPriceExceptions ///////////////////////////
INSERT INTO OSFA_DB.[dbo].[OT_ItemsPriceExceptions]
           ([CompNo]
           ,[SalesmanNo]
           ,[CustomerNo]
           ,[ItemNo]
           ,[UnitCode]
           ,[StartDate]
           ,[EndDate]
           ,[SellPrice]
           ,[TaxPerc]
           ,[TaxType]
           ,[DiscountPercent]
           ,[UseInReturn]
           ,[UseInSales]
           ,[SellPrice2]
           ,[SellPrice3]
           ,[Qty]
		   ,Tax_1_Type
		   ,Tax_1_Perc
		   ,Tax_2_Type
		   ,Tax_2_Perc)

SELECT    distinct    ItemsPriceExceptions.CompanyID, OSFA_DB.dbo.OT_CustomerMF.SalesmanNo, ItemsPriceExceptions.CustomerID, ItemsPriceExceptions.ItemCode,  ItemsUnits.ID, ItemsPriceExceptions.StartDate,
                          ItemsPriceExceptions.EndDate, ItemsPriceExceptions.Price, ItemsPriceExceptions.Tax, ItemsPriceExceptions.TaxType, ItemsPriceExceptions.DiscountPercent, ItemsPriceExceptions.UseInReturn, 
                         ItemsPriceExceptions.UseInSales, ItemsPriceExceptions.SellPrice2, ItemsPriceExceptions.SellPrice3, ItemsPriceExceptions.Qty, ISNULL(ItemsPriceExceptions.TaxType1, 0) AS Expr1, 
                         ISNULL(ItemsPriceExceptions.Tax1, 0) AS Expr2, ISNULL(ItemsPriceExceptions.TaxType2, 0) AS Expr3, ISNULL(ItemsPriceExceptions.Tax2, 0) AS Expr4
FROM            ItemsPriceExceptions INNER JOIN
                         OSFA_DB.dbo.OT_CustomerMF ON ItemsPriceExceptions.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND ItemsPriceExceptions.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON ItemsPriceExceptions.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND ItemsPriceExceptions.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo INNER JOIN
                         ItemsUnits ON ItemsPriceExceptions.CompanyID = ItemsUnits.CompanyID AND ItemsPriceExceptions.UnitID = ItemsUnits.ID
WHERE        (ItemsPriceExceptions.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, ItemsPriceExceptions.StartDate)) <= @SendDate) 
                         AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, ItemsPriceExceptions.EndDate)) >= @SendDate) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
END
SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_ItemsPriceExceptions [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

--////// OT_SalesmanTransactionsSerialsMulti ///////////////////////////

IF @ClientActive <> 27
BEGIN
-- Sales Order
	SET @BeginTime = Convert(varchar(20),GetDate(),108)

	UPDATE       SalesPersonTransactionsSerialsMulti
	SET                OrderTakingNextSerial = Serial
	FROM            (SELECT        MAX(ISNULL(OSFA_DB.dbo.OT_OrderHF.OrderNo, 0)) + 1 AS Serial, Customers.Reference2 AS RefLink, Customers.CompanyID, OSFA_DB.dbo.OT_OrderHF.SalesmanNo
							   FROM            OSFA_DB.dbo.OT_OrderHF INNER JOIN
														Customers ON OSFA_DB.dbo.OT_OrderHF.CompNo = Customers.CompanyID AND OSFA_DB.dbo.OT_OrderHF.CustomerNo = Customers.ID
							   WHERE        (OSFA_DB.dbo.OT_OrderHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_OrderHF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_OrderHF.OrderYear =  YEAR(@SendDate))
							   GROUP BY Customers.Reference2, Customers.CompanyID, OSFA_DB.dbo.OT_OrderHF.SalesmanNo) AS Sr_Tbl INNER JOIN
							 SalesPersonTransactionsSerialsMulti ON Sr_Tbl.CompanyID = SalesPersonTransactionsSerialsMulti.CompanyID AND Sr_Tbl.SalesmanNo = SalesPersonTransactionsSerialsMulti.SalesPersonID AND 
							 Sr_Tbl.RefLink = SalesPersonTransactionsSerialsMulti.RefLink
	WHERE        (SalesPersonTransactionsSerialsMulti.SalesPersonID = @SalesmanNo) AND (SalesPersonTransactionsSerialsMulti.CompanyID = @CompNo) AND 
							 (SalesPersonTransactionsSerialsMulti.SerYear = YEAR(@SendDate))

-- Invoices

	UPDATE       SalesPersonTransactionsSerialsMulti
	SET                SalesInvoiceNextSerial = Serial
	FROM            (SELECT        MAX(ISNULL(OSFA_DB.dbo.OT_InvoiceHF.VouNo, 0)) + 1 AS Serial, Customers.Reference2 AS RefLink, Customers.CompanyID, OSFA_DB.dbo.OT_InvoiceHF.SalesmanNo
							   FROM            OSFA_DB.dbo.OT_InvoiceHF INNER JOIN
														Customers ON OSFA_DB.dbo.OT_InvoiceHF.CompNo = Customers.CompanyID AND OSFA_DB.dbo.OT_InvoiceHF.CustomerNo = Customers.ID
							   WHERE        (OSFA_DB.dbo.OT_InvoiceHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_InvoiceHF.VouYear =  YEAR(@SendDate) AND (OSFA_DB.dbo.OT_InvoiceHF.VouType=1))
							   GROUP BY Customers.Reference2, Customers.CompanyID, OSFA_DB.dbo.OT_InvoiceHF.SalesmanNo) AS Sr_Tbl INNER JOIN
							 SalesPersonTransactionsSerialsMulti ON Sr_Tbl.CompanyID = SalesPersonTransactionsSerialsMulti.CompanyID AND Sr_Tbl.SalesmanNo = SalesPersonTransactionsSerialsMulti.SalesPersonID AND 
							 Sr_Tbl.RefLink = SalesPersonTransactionsSerialsMulti.RefLink
	WHERE        (SalesPersonTransactionsSerialsMulti.SalesPersonID = @SalesmanNo) AND (SalesPersonTransactionsSerialsMulti.CompanyID = @CompNo) AND 
							 (SalesPersonTransactionsSerialsMulti.SerYear = YEAR(@SendDate))

-- Sales Return
	UPDATE       SalesPersonTransactionsSerialsMulti
	SET                ReturnSalesNextSerial = Serial
	FROM            (SELECT        MAX(ISNULL(OSFA_DB.dbo.OT_InvoiceHF.VouNo, 0)) + 1 AS Serial, Customers.Reference2 AS RefLink, Customers.CompanyID, OSFA_DB.dbo.OT_InvoiceHF.SalesmanNo
							   FROM            OSFA_DB.dbo.OT_InvoiceHF INNER JOIN
														Customers ON OSFA_DB.dbo.OT_InvoiceHF.CompNo = Customers.CompanyID AND OSFA_DB.dbo.OT_InvoiceHF.CustomerNo = Customers.ID
							   WHERE        (OSFA_DB.dbo.OT_InvoiceHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_InvoiceHF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_InvoiceHF.VouYear =  YEAR(@SendDate) AND (OSFA_DB.dbo.OT_InvoiceHF.VouType=2))
							   GROUP BY Customers.Reference2, Customers.CompanyID, OSFA_DB.dbo.OT_InvoiceHF.SalesmanNo) AS Sr_Tbl INNER JOIN
							 SalesPersonTransactionsSerialsMulti ON Sr_Tbl.CompanyID = SalesPersonTransactionsSerialsMulti.CompanyID AND Sr_Tbl.SalesmanNo = SalesPersonTransactionsSerialsMulti.SalesPersonID AND 
							 Sr_Tbl.RefLink = SalesPersonTransactionsSerialsMulti.RefLink
	WHERE        (SalesPersonTransactionsSerialsMulti.SalesPersonID = @SalesmanNo) AND (SalesPersonTransactionsSerialsMulti.CompanyID = @CompNo) AND 
							 (SalesPersonTransactionsSerialsMulti.SerYear = YEAR(@SendDate))

-- Return Order
	UPDATE       SalesPersonTransactionsSerialsMulti
	SET                ReturnOrderNextSerial = Serial
	FROM            (SELECT        MAX(ISNULL(OSFA_DB.dbo.OT_ReturnOrderHF.VouNo, 0)) + 1 AS Serial, Customers.Reference2 AS RefLink, Customers.CompanyID, OSFA_DB.dbo.OT_ReturnOrderHF.SalesmanNo
							   FROM            OSFA_DB.dbo.OT_ReturnOrderHF INNER JOIN
														Customers ON OSFA_DB.dbo.OT_ReturnOrderHF.CompNo = Customers.CompanyID AND OSFA_DB.dbo.OT_ReturnOrderHF.CustomerNo = Customers.ID
							   WHERE        (OSFA_DB.dbo.OT_ReturnOrderHF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_ReturnOrderHF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_ReturnOrderHF.VouYear =  YEAR(@SendDate))
							   GROUP BY Customers.Reference2, Customers.CompanyID, OSFA_DB.dbo.OT_ReturnOrderHF.SalesmanNo) AS Sr_Tbl INNER JOIN
							 SalesPersonTransactionsSerialsMulti ON Sr_Tbl.CompanyID = SalesPersonTransactionsSerialsMulti.CompanyID AND Sr_Tbl.SalesmanNo = SalesPersonTransactionsSerialsMulti.SalesPersonID AND 
							 Sr_Tbl.RefLink = SalesPersonTransactionsSerialsMulti.RefLink
	WHERE        (SalesPersonTransactionsSerialsMulti.SalesPersonID = @SalesmanNo) AND (SalesPersonTransactionsSerialsMulti.CompanyID = @CompNo) AND 
							 (SalesPersonTransactionsSerialsMulti.SerYear = YEAR(@SendDate))

-- Payment


	UPDATE       SalesPersonTransactionsSerialsMulti
	SET                ReceiptNextSerial = Serial
	FROM            (SELECT        MAX(ISNULL(OSFA_DB.dbo.OT_Payments.VouNo, 0)) + 1 AS Serial, Customers.Reference2 AS RefLink, Customers.CompanyID, OSFA_DB.dbo.OT_Payments.SalesmanNo
							   FROM            OSFA_DB.dbo.OT_Payments INNER JOIN
														Customers ON OSFA_DB.dbo.OT_Payments.CompNo = Customers.CompanyID AND OSFA_DB.dbo.OT_Payments.CustomerNo = Customers.ID
							   WHERE        (OSFA_DB.dbo.OT_Payments.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_Payments.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_Payments.VouYear =  YEAR(@SendDate))
							   GROUP BY Customers.Reference2, Customers.CompanyID, OSFA_DB.dbo.OT_Payments.SalesmanNo) AS Sr_Tbl INNER JOIN
							 SalesPersonTransactionsSerialsMulti ON Sr_Tbl.CompanyID = SalesPersonTransactionsSerialsMulti.CompanyID AND Sr_Tbl.SalesmanNo = SalesPersonTransactionsSerialsMulti.SalesPersonID AND 
							 Sr_Tbl.RefLink = SalesPersonTransactionsSerialsMulti.RefLink
	WHERE        (SalesPersonTransactionsSerialsMulti.SalesPersonID = @SalesmanNo) AND (SalesPersonTransactionsSerialsMulti.CompanyID = @CompNo) AND 
							 (SalesPersonTransactionsSerialsMulti.SerYear = YEAR(@SendDate))


	INSERT INTO OSFA_DB.[dbo].[OT_SalesmanTransactionsSerialsMulti]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[SerYear]
			   ,[RefLink]
			   ,[OrderTakingNextSerial]
			   ,[TransferOrderNextSerial]
			   ,[SalesInvoiceNextSerial]
			   ,[ReturnSalesNextSerial]
			   ,[ReceiptNextSerial]
			   ,[ConsNextSerial]
			   ,[CustStockNextSerial]
			   ,[CompetitiveItemsInfoNextSerial]
			   ,[UnLoadOrdersNextSerials]
			   ,[SalesmanStockNextSerial]
			   ,[ReturnOrderNextSerial]
			   ,[VanTransferNextSerial]
			   ,[SalesQuotationNextSerial])
	SELECT        CompanyID, SalesPersonID, SerYear, RefLink, OrderTakingNextSerial, TransferOrderNextSerial, SalesInvoiceNextSerial, ReturnSalesNextSerial, ReceiptNextSerial, ConsNextSerial, CustStockNextSerial, 
							 CompetitiveItemsInfoNextSerial, UnLoadOrdersNextSerials, SalesmanStockNextSerial, ReturnOrderNextSerial, VanTransferNextSerial, SalesQuotationNextSerial
	FROM            SalesPersonTransactionsSerialsMulti
	WHERE        (CompanyID = @CompNo) AND (SalesPersonID = @SalesmanNo) AND (SerYear = YEAR(@SendDate))

	SET @EndTime = Convert(varchar(20),GetDate(),108)
	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_SalesmanTransactionsSerialsMulti [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

END
--///////////////////////IS GPS Collect In Customer/////////////////////////////////////////////
/*
SET @BeginTime = Convert(varchar(20),GetDate(),108)

UPDATE       OSFA_DB.dbo.OT_CustomerMF
SET                IsCollectedGPS = CASE WHEN OSFA_DB.dbo.OT_GPSLog.CompNo IS NULL THEN 0 ELSE 1 END
FROM            OSFA_DB.dbo.OT_CustomerMF LEFT OUTER JOIN
                         OSFA_DB.dbo.OT_GPSLog ON OSFA_DB.dbo.OT_CustomerMF.CompNo = OSFA_DB.dbo.OT_GPSLog.CompNo AND 
                         OSFA_DB.dbo.OT_CustomerMF.CustomerNo = OSFA_DB.dbo.OT_GPSLog.CustomerNo
WHERE        (OSFA_DB.dbo.OT_CustomerMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Update Customers GPS In OT_CustomerMF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
*/
--///////////////////////ItemsPriority/////////////////////////////////////////////

SET @BeginTime = Convert(varchar(20),GetDate(),108)

IF @ClientActive = 11
BEGIN

	INSERT INTO OSFA_DB.[dbo].[OT_ItemsPriority]
			   ([AutoID]
			   ,[CompanyID]
			   ,[ItemCode]
			   ,[UseInSuggestedOrder]
			   ,[UnitID]
			   ,[Qty]
			   ,[CustTypeID]
			   ,[SalesmanNo],TargetType)
SELECT     ROW_NUMBER() OVER(Order by ItemCode) ,  CompanyID, ItemCode, UseInSuggestedOrder, UnitID, Qty, CustTypeID, SalespersonID, TargetType
FROM            (SELECT         SalespersonTargetReferenceFocusItem.CompanyID , SalespersonTargetReferenceFocusItem.ItemCode, 0 AS UseInSuggestedOrder, Items.UnitID, 0 AS Qty, 0 AS CustTypeID, 
                                                    SalespersonTargetReferenceFocusItem.SalespersonID, 1 AS TargetType
                          FROM            SalespersonTargetReferenceFocusItem INNER JOIN
                                                    Items ON SalespersonTargetReferenceFocusItem.CompanyID = Items.CompanyID AND SalespersonTargetReferenceFocusItem.ItemCode = Items.ItemCode
                          WHERE        (SalespersonTargetReferenceFocusItem.CompanyID = @CompNo) AND (SalespersonTargetReferenceFocusItem.SalespersonID = @SalesmanNo)
                          UNION ALL
                          SELECT        Items.CompanyID, Items.ItemCode, 0 AS UseInSuggestedOrder, Items.UnitID, 0 AS Qty, 0 AS CustTypeID, @SalesmanNo AS Expr2, 2 AS TargetType
                          FROM            Items INNER JOIN
                                                   SalespersonCustStockItemsTargetLink ON Items.CompanyID = SalespersonCustStockItemsTargetLink.CompanyID AND Items.ItemCode = SalespersonCustStockItemsTargetLink.ItemCode
                          WHERE        (SalespersonCustStockItemsTargetLink.CompanyID = @CompNo) AND (SalespersonCustStockItemsTargetLink.PositionsID = @PositionsID) AND 
                                                   (SalespersonCustStockItemsTargetLink.TargetMonth = MONTH(@SendDate)) AND (SalespersonCustStockItemsTargetLink.TargetYear = YEAR(@SendDate))) AS Tbl
END
ELSE
BEGIN
			INSERT INTO OSFA_DB.[dbo].[OT_ItemsPriority]
			   ([AutoID]
			   ,[CompanyID]
			   ,[ItemCode]
			   ,[UseInSuggestedOrder]
			   ,[UnitID]
			   ,[Qty]
			   ,[CustTypeID]
			   ,[SalesmanNo])

				SELECT        AutoID, CompanyID, ItemCode, UseInSuggestedOrder, UnitID, Qty, CustTypeID,@SalesmanNo
				FROM            ItemsPriority
				WHERE        (CompanyID = @CompNo)
END



IF @ClientActive = 35
BEGIN
	set @AccStatDays =-90
	set @AccStatFromDate =GETDATE()
	SET @AccStatFromDate=DATEADD(DAY,@AccStatDays,@AccStatFromDate)
	PRINT @AccStatFromDate


	;WITH TMPAccStat AS(
		SELECT        CustomerNo, SUM(Debit- Credit) AS BAL
		FROM            OSFA_DB.dbo.OT_StateAccBalance
		WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (TrDate < @AccStatFromDate)
		GROUP BY CustomerNo
	)

	INSERT INTO OSFA_DB.[dbo].[OT_StateAccBalance]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[CustomerNo]
			   ,[TrType]
			   ,[TrNo]
			   ,[TrSer]
			   ,[TrDate]
			   ,[TrName]
			   ,[Debit]
			   ,[Credit]
			   ,[Notes]
			   ,[Balance])
	SELECT @CompNo, @SalesmanNo,CustomerNo, 'Rounded Balance',0,0,@AccStatFromDate,'Rounded Balance',case when Bal >0 then BAL else 0 end  ,case when Bal <0 then  abs (BAL) else 0 end ,'',Bal
	FROM TMPAccStat

	DELETE
	FROM            OSFA_DB.dbo.OT_StateAccBalance
	WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (TrDate < @AccStatFromDate)
END	
--/////////////////// Customers Groups ////////////////////////////////////////////////
if @ClientActive=13 and @CompNo=3

begin

INSERT INTO OSFA_DB.[dbo].[OT_CustomersGroups]
           ([CompNo]
           ,[SalesmanNo]
           ,[Group_ID]
           ,[ArDesc]
           ,[EngDesc]
           ,[Ref1]
           ,[Ref2])
 
SELECT        CompanyID,@SalesmanNo , GroupID, Name, ForeignName, Reference1, Reference2
FROM            CustomersGroups
WHERE        (CompanyID = @CompNo) and GroupID>=101
End
Else

Begin

INSERT INTO OSFA_DB.[dbo].[OT_CustomersGroups]
           ([CompNo]
           ,[SalesmanNo]
           ,[Group_ID]
           ,[ArDesc]
           ,[EngDesc]
           ,[Ref1]
           ,[Ref2])
 
SELECT        CompanyID,@SalesmanNo , GroupID, Name, ForeignName, Reference1, Reference2
FROM            CustomersGroups
WHERE        (CompanyID = @CompNo)
END
--=======================================================================================
SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_ItemsPriority, OT_CustomersGroups [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')


if @ClientActive <>74 
begin
SET @BeginTime = Convert(varchar(20),GetDate(),108)

Declare  @OT_ActionLog_Tmp TABLE (
	AutoID [numeric](30, 0) ,
	CompNo [smallint],
	ActionID [nvarchar](20) ,
	TimeStamp [datetime] ,
	SalesmanID [nvarchar](20),
	Data1 [nvarchar](1000) ,
	Data2 [nvarchar](1000) ,
	Data3 [nvarchar](1000) ,
	Data4 [nvarchar](1000) ,
	Data5 [nvarchar](1000) ,
	GpsX [nchar](50) ,
	GpsY [nchar](50) ,
	RouteID [int],
	primary key(AutoID))

DELETE FROM @OT_ActionLog_Tmp
INSERT INTO @OT_ActionLog_Tmp
SELECT        AutoID, CompNo, ActionID, TimeStamp, SalesmanID, Data1, Data2, Data3, Data4, Data5, GpsX, GpsY, RouteID
FROM            OSFA_DB.dbo.OT_ActionLog with(nolock)
WHERE (CompNo = @CompNo) AND (SalesmanID = @SalesmanNo) AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, TimeStamp)) = @SendDate)
AND NOT(ActionID IN (49))

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Insert to Temp Table @OT_ActionLog_Tmp [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

SET @BeginTime = Convert(varchar(20),GetDate(),108)

UPDATE       OSFA_DB.dbo.OT_SalesmanRoute
SET                Visited = 1, VisitOrder = 9999
From OSFA_DB.dbo.OT_SalesmanRoute AS SalesRoute Inner Join @OT_ActionLog_Tmp AS i ON
	SalesRoute.CompNo = i.CompNo AND
	CAST(SalesRoute.CustomerNo AS Varchar(20)) = i.Data1 AND
	SalesRoute.SalesmanNo = i.SalesmanID AND
	i.ActionID = '0' AND
	(CONVERT(Date,TimeStamp) = @SendDate)
WHERE        (i.CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (RouteDate = @SendDate)
end
--UPDATE       OSFA_DB.dbo.OT_SalesmanRoute
--SET                Visited = 1, VisitOrder = 9999
--WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (RouteDate = @SendDate) AND (CustomerNo IN
--                             (SELECT        Data1
--                                FROM            @OT_ActionLog_Tmp
--                                WHERE        (CompNo = @CompNo) AND (SalesmanID = @SalesmanNo) AND (ActionID = N'0') AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, TimeStamp)) = @SendDate)))


IF @ClientActive = 27 OR @ClientActive = 30 or @ClientActive=136 or @ClientActive =67 Or @ClientActive = 50 or @ClientActive=82
BEGIN	
	goto SKIP_PostPonedCustomers
END

UPDATE       OSFA_DB.dbo.OT_SalesmanRoute
SET                Visited = 1, VisitOrder = 8888
FROM OSFA_DB.dbo.OT_SalesmanRoute AS OT_SalesmanRoute INNER JOIN [dbo].[Fun_GetPostPonedCustomers](@CompNo,@SendDate,@SalesmanNo) AS Fun_GetPostPonedCustomers ON
OT_SalesmanRoute.CompNo=Fun_GetPostPonedCustomers.CompanyID AND OT_SalesmanRoute.[CustomerNo]=Fun_GetPostPonedCustomers.CustomerNo
WHERE        (OT_SalesmanRoute.CompNo = @CompNo) AND (OT_SalesmanRoute.SalesmanNo = @SalesmanNo) AND (OT_SalesmanRoute.RouteDate = @SendDate)

SKIP_PostPonedCustomers:

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Update OT_SalesmanRoute [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')


SET @BeginTime = Convert(varchar(20),GetDate(),108)

UPDATE   OSFA_DB.dbo.OT_CustomerMF
SET                StartVisitTime = convert(varchar(20), Xtbl.EntryTime,105) + ' | ' + convert(varchar(20), Xtbl.EntryTime,108), 
				   EndVisitTime = convert(varchar(20), Xtbl.LeaveTime,105) + ' | ' + convert(varchar(20), Xtbl.LeaveTime,108)
FROM            OSFA_DB.dbo.OT_CustomerMF INNER JOIN
                             (SELECT        CompNo, Data1, TimeStamp AS EntryTime,
                                                             (SELECT        TOP (1) TimeStamp
                                                                FROM            @OT_ActionLog_Tmp AS i
                                                                WHERE        (CompNo = @CompNo) AND (ActionID = N'3') AND (J.Data1 = Data1) AND (SalesmanID = @SalesmanNo) AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, TimeStamp)) = @SendDate) AND 
                                                                                         (TimeStamp >= J.TimeStamp)
                                                                ORDER BY TimeStamp) AS LeaveTime
                                FROM            @OT_ActionLog_Tmp AS J
                                WHERE        (CompNo = @CompNo) AND (SalesmanID = @SalesmanNo) AND (ActionID = N'0') AND (DATEADD(DAY, 0, DATEDIFF(DAY, 0, TimeStamp)) = @SendDate)) AS Xtbl ON 
                         Xtbl.CompNo = OSFA_DB.dbo.OT_CustomerMF.CompNo AND Xtbl.Data1 = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
WHERE        (OSFA_DB.dbo.OT_CustomerMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND @ClientActive NOT IN(136,142)


SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Update StartVisitTime, EndVisitTime In OT_CustomerMF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

SET @BeginTime = Convert(varchar(20),GetDate(),108)

UPDATE       OSFA_DB.dbo.OT_CustomerMF
SET       HaveTrans = 1         
FROM            (SELECT DISTINCT CompanyID, CustomerID, SalesPersonID
                          FROM            TransactionsHeaders
                          WHERE        (CompanyID = @CompNo) AND (TransactionTypeID = 1) AND (TransactionDate = @SendDate) AND (SalesPersonID = @SalesmanNo)
                          UNION
                          SELECT DISTINCT CompanyID, CustomerID, SalesPersonID
                          FROM            OrdersHeaders
                          WHERE        (CompanyID = @CompNo) AND (OrderDate = @SendDate) AND (SalesPersonID = @SalesmanNo)) AS Xtbl INNER JOIN
                         OSFA_DB.dbo.OT_CustomerMF ON Xtbl.SalesPersonID = OSFA_DB.dbo.OT_CustomerMF.SalesmanNo AND Xtbl.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND 
                         Xtbl.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo

/*
UPDATE       OSFA_DB.dbo.OT_CustomerMF
SET                HaveTrans = 1
WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (CustomerNo IN
                             (SELECT        CustomerID
                                FROM            TransactionsHeaders
                                WHERE        (CompanyID = @CompNo) AND (TransactionTypeID = 1) AND (TransactionDate = @SendDate) AND (SalesPersonID = @SalesmanNo)))

UPDATE       OSFA_DB.dbo.OT_CustomerMF
SET                HaveTrans = 1
WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (CustomerNo IN
                             (SELECT        CustomerID
                                FROM            OrdersHeaders
                                WHERE        (CompanyID = @CompNo) AND (OrderDate = @SendDate) AND (SalesPersonID = @SalesmanNo)))
*/
SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Update HaveTrans In OT_CustomerMF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')


--=======================================================================================
/*
SET @BeginTime = Convert(varchar(20),GetDate(),108)

UPDATE       OSFA_DB.dbo.OT_CustomerMF
SET                [Group_ID] = ISNULL([dbo].[Customers].Group_ID,0)
FROM            OSFA_DB.dbo.OT_CustomerMF INNER JOIN
                         [dbo].[Customers] ON OSFA_DB.dbo.OT_CustomerMF.CompNo = [dbo].[Customers].CompanyID AND OSFA_DB.dbo.OT_CustomerMF.CustomerNo = [dbo].[Customers].ID 
WHERE        (OSFA_DB.dbo.OT_CustomerMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Update Group_ID In OT_CustomerMF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
*/
--///////////////////  Image Types ////////////////////////////////////////////////

SET @BeginTime = Convert(varchar(20),GetDate(),108)

INSERT INTO OSFA_DB.[dbo].OT_ImageTypes
           ([CompNo]
           ,[SalesmanNo]
           ,[ImageType_ID]
           ,[ArDesc]
           ,[EngDesc]
           ,[Ref1]
           ,[Ref2]
		   ,UseFor)
 
SELECT        CompanyID,@SalesmanNo , ID, Name, [ShortName], Reference1, Reference2,UseFor
FROM            ImageTypes
WHERE        (CompanyID = @CompNo)

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_ImageTypes [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

--/////////////////// UPDATE OT_ItemsMF ////////////////////////////////////////////////

IF @ClientActive = 27 or @ClientActive = 136 or @ClientActive=82
BEGIN
	goto Skip_VanCustody
END

SET @BeginTime = Convert(varchar(20),GetDate(),108)

if @ClientActive = 38
Begin
UPDATE       OSFA_DB.dbo.OT_ItemsMF
SET                Van_StandardStock = xtbl.MinQty, Packing =case when xtbl.UsedInUploadOrder = 0 then '' else xtbl.FillSize end  , Van_StandardStock_Max = xtbl.MaxQty,VanCustodyUnitSerial=xtbl.VanCustodyUnitSerial
FROM            (SELECT        TransfersOrder_Auto.CompanyID, TransfersOrder_Auto.SalesPersonID, Items.ItemCode, 
									SUM(dbo.GetItemSmallUnitQty(@CompNo, Items.ItemCode, TransfersOrder_Auto.UnitID, TransfersOrder_Auto.Quantity)) AS MinQty, 
                                    SUM(dbo.GetItemSmallUnitQty(@CompNo, Items.ItemCode, TransfersOrder_Auto.UnitID, TransfersOrder_Auto.MaxQty)) AS MaxQty, Items.FillSize, items.UsedInUploadOrder,Items.VanCustodyUnitSerial
                           FROM            OSFA_DB.dbo.OT_ItemsMF AS OT_ItemsMF_1 INNER JOIN
                                                    Items ON OT_ItemsMF_1.CompNo = Items.CompanyID AND OT_ItemsMF_1.ItemNo = Items.ItemCode INNER JOIN
                                                    TransfersOrder_Auto ON OT_ItemsMF_1.CompNo = TransfersOrder_Auto.CompanyID AND OT_ItemsMF_1.SalesmanNo = TransfersOrder_Auto.SalesPersonID AND 
                                                    OT_ItemsMF_1.ItemNo = TransfersOrder_Auto.ItemCode
                           WHERE        (OT_ItemsMF_1.CompNo = @CompNo) AND (OT_ItemsMF_1.SalesmanNo = @SalesmanNo)
                           GROUP BY TransfersOrder_Auto.CompanyID, TransfersOrder_Auto.SalesPersonID, Items.ItemCode, Items.FillSize , Items.UsedInUploadOrder,Items.VanCustodyUnitSerial) AS xtbl INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON xtbl.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND xtbl.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND xtbl.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
END
Else 
Begin 
UPDATE       OSFA_DB.dbo.OT_ItemsMF
SET                Van_StandardStock = xtbl.MinQty, Packing = xtbl.FillSize, Van_StandardStock_Max = xtbl.MaxQty,VanCustodyUnitSerial=xtbl.VanCustodyUnitSerial
FROM            (SELECT        TransfersOrder_Auto.CompanyID, TransfersOrder_Auto.SalesPersonID, Items.ItemCode, 
									SUM(dbo.GetItemSmallUnitQty(@CompNo, Items.ItemCode, TransfersOrder_Auto.UnitID, TransfersOrder_Auto.Quantity)) AS MinQty, 
                                    SUM(dbo.GetItemSmallUnitQty(@CompNo, Items.ItemCode, TransfersOrder_Auto.UnitID, TransfersOrder_Auto.MaxQty)) AS MaxQty, Items.FillSize,Items.VanCustodyUnitSerial
                           FROM            OSFA_DB.dbo.OT_ItemsMF AS OT_ItemsMF_1 INNER JOIN
                                                    Items ON OT_ItemsMF_1.CompNo = Items.CompanyID AND OT_ItemsMF_1.ItemNo = Items.ItemCode INNER JOIN
                                                    TransfersOrder_Auto ON OT_ItemsMF_1.CompNo = TransfersOrder_Auto.CompanyID AND OT_ItemsMF_1.SalesmanNo = TransfersOrder_Auto.SalesPersonID AND 
                                                    OT_ItemsMF_1.ItemNo = TransfersOrder_Auto.ItemCode
                           WHERE        (OT_ItemsMF_1.CompNo = @CompNo) AND (OT_ItemsMF_1.SalesmanNo = @SalesmanNo)
                           GROUP BY TransfersOrder_Auto.CompanyID, TransfersOrder_Auto.SalesPersonID, Items.ItemCode, Items.FillSize,Items.VanCustodyUnitSerial) AS xtbl INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON xtbl.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND xtbl.SalesPersonID = OSFA_DB.dbo.OT_ItemsMF.SalesmanNo AND xtbl.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo


END
/*
UPDATE       OSFA_DB.dbo.OT_ItemsMF
SET                 Van_StandardStock = SUM(dbo.GetItemSmallUnitQty (@CompNo, Items.ItemCode,TransfersOrder_Auto.UnitID,TransfersOrder_Auto.Quantity)),
                    Van_StandardStock_Max = SUM(dbo.GetItemSmallUnitQty (@CompNo, Items.ItemCode,TransfersOrder_Auto.UnitID,TransfersOrder_Auto.MaxQty)),
					Packing =  case when @ClientActive=3 then 0 else Items.FillSize end
FROM            OSFA_DB.dbo.OT_ItemsMF INNER JOIN
                         Items ON OSFA_DB.dbo.OT_ItemsMF.CompNo = Items.CompanyID AND OSFA_DB.dbo.OT_ItemsMF.ItemNo = Items.ItemCode INNER JOIN
                         TransfersOrder_Auto ON OSFA_DB.dbo.OT_ItemsMF.CompNo = TransfersOrder_Auto.CompanyID AND OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = TransfersOrder_Auto.SalesPersonID AND 
                         OSFA_DB.dbo.OT_ItemsMF.ItemNo = TransfersOrder_Auto.ItemCode
WHERE        (OSFA_DB.dbo.OT_ItemsMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
*/

--UPDATE       OSFA_DB.dbo.OT_ItemsMF
--SET                Van_StandardStock = dbo.GetItemSmallUnitQty(TransfersOrder_Auto.CompanyID, TransfersOrder_Auto.ItemCode, TransfersOrder_Auto.UnitID,ABS(dbo.GetItemOrgUnitQty(TransfersOrder_Auto.CompanyID, TransfersOrder_Auto.ItemCode, TransfersOrder_Auto.UnitID, ABS(ISNULL(TransfersOrder_Auto.Quantity,0))))), 
--						 Packing =  case when @ClientActive=3 then 0 else Items.FillSize end,
--						 Van_StandardStock_Max = dbo.GetItemSmallUnitQty(TransfersOrder_Auto.CompanyID, TransfersOrder_Auto.ItemCode, TransfersOrder_Auto.UnitID,ABS(dbo.GetItemOrgUnitQty(TransfersOrder_Auto.CompanyID, TransfersOrder_Auto.ItemCode, TransfersOrder_Auto.UnitID, ABS(ISNULL(TransfersOrder_Auto.MaxQty,0)))))
--FROM            OSFA_DB.dbo.OT_ItemsMF INNER JOIN
--                         Items ON OSFA_DB.dbo.OT_ItemsMF.CompNo = Items.CompanyID AND OSFA_DB.dbo.OT_ItemsMF.ItemNo = Items.ItemCode LEFT OUTER JOIN
--                         TransfersOrder_Auto ON OSFA_DB.dbo.OT_ItemsMF.CompNo = TransfersOrder_Auto.CompanyID AND OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = TransfersOrder_Auto.SalesPersonID AND 
--                         OSFA_DB.dbo.OT_ItemsMF.ItemNo = TransfersOrder_Auto.ItemCode
--WHERE        (OSFA_DB.dbo.OT_ItemsMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Update Van_StandardStock In OT_ItemsMF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

Skip_VanCustody:

SET @BeginTime = Convert(varchar(20),GetDate(),108)
--///////////////////   [OT_CustomersItemsAssigment] ////////////////////////////////////////////////
--By Firas
If @ClientActive= 85 and   @CompNo =1
Begin
if @SalesmanGroupID=3
begin
        INSERT INTO OSFA_DB.[dbo].[OT_CustomersItemsAssigment]
				([CompanyID]
				,[SalesmanNo]
				,[CustomerID]
				,[ItemCode])

	SELECT DISTINCT InvoiceDeliveryHF.CompNo, @SalesmanNo AS SalesmanNo, InvoiceDeliveryHF.CustomerNo, InvoiceDeliveryDF.ItemNo
FROM     InvoiceDeliveryHF INNER JOIN
                  InvoiceDeliveryDF ON InvoiceDeliveryHF.CompNo = InvoiceDeliveryDF.CompNo AND InvoiceDeliveryHF.VouNo = InvoiceDeliveryDF.VouNo AND InvoiceDeliveryHF.VouType = InvoiceDeliveryDF.VouType AND 
                  InvoiceDeliveryHF.VouYear = InvoiceDeliveryDF.VouYear INNER JOIN
                  OSFA_DB..OT_CustomerMF OT_CustomerMF ON OT_CustomerMF.CompNo = InvoiceDeliveryHF.CompNo and OT_CustomerMF.CustomerNo=InvoiceDeliveryHF.CustomerNo
				  AND OT_CustomerMF.SalesmanNo =@SalesmanNo
WHERE  (InvoiceDeliveryHF.CompNo = @CompNo) and    (OT_CustomerMF.CustomerRef1 not in ( 'C16500') )
Union All
SELECT xbt.CompanyID as CompNo, @SalesmanNo as SalesmanNo, Customers_1.ID as CustomerNo , xbt.ItemNo as ItemNo
FROM     (SELECT DISTINCT Customers.CompanyID, Customers.Reference1, InvoiceDeliveryDF.ItemNo
                  FROM      InvoiceDeliveryHF INNER JOIN
                                    InvoiceDeliveryDF ON InvoiceDeliveryHF.CompNo = InvoiceDeliveryDF.CompNo AND InvoiceDeliveryHF.VouNo = InvoiceDeliveryDF.VouNo AND InvoiceDeliveryHF.VouType = InvoiceDeliveryDF.VouType AND 
                                    InvoiceDeliveryHF.VouYear = InvoiceDeliveryDF.VouYear INNER JOIN
                                    Customers ON InvoiceDeliveryHF.CompNo = Customers.CompanyID AND InvoiceDeliveryHF.CustomerNo = Customers.ID
                  WHERE   (Customers.Reference1 = N'C16500') and Customers.CompanyID=@CompNo) AS xbt INNER JOIN
                  Customers AS Customers_1 ON xbt.CompanyID = Customers_1.CompanyID AND xbt.Reference1 = Customers_1.Reference1

End
end
Else
begin
INSERT INTO OSFA_DB.[dbo].[OT_CustomersItemsAssigment]
				([CompanyID]
				,[SalesmanNo]
				,[CustomerID]
				,[ItemCode])
SELECT        CompanyID, @SalesmanNo AS Expr1, CustomerID, ItemCode
FROM            CustomersItemsAssigment
WHERE        (CompanyID = @CompNo) AND (PositionsID = @PositionsID)

end

--/////////////////// OT_ItemsUnitsBarcode ////////////////////////////////////////////////
 
 IF @ClientActive = 24	 
BEGIN 
	If @SalesmanNo > 9000
		BEGIN 
				INSERT INTO OSFA_DB.[dbo].[OT_ItemsUnitsBarcode]
				   ([CompNo]
				   ,[SalesmanNo]
				   ,[ItemCode]
				   ,[Unit]
				   ,[Barcode])
				SELECT DISTINCT * FROM(
				SELECT        Items.CompanyID, @SalesmanNo AS SalesmanNo, Items.ItemCode, dbo.trim( Items.UnitID) AS UnitID, 
		
				 case when @ClientActive=24 and @SalesmanNo>9989 then items.Reference3  else dbo.trim(Items.Barcode) end  AS Barcode
				FROM            Items INNER JOIN  
								OSFA_DB.dbo.OT_ItemsMF ON Items.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND Items.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
				WHERE         (NOT (Items.Barcode IS NULL))  AND(Items.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)

				UNION ALL
				SELECT        CompanyID, @SalesmanNo AS SalesmanNo, ItemsUnitsDetails.ItemCode, dbo.trim( UnitID) AS UnitID, dbo.trim(ItemsUnitsDetails.Barcode) AS Barcode
				FROM            ItemsUnitsDetails  INNER JOIN  
								OSFA_DB.dbo.OT_ItemsMF ON ItemsUnitsDetails.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND ItemsUnitsDetails.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
				WHERE        (NOT (ItemsUnitsDetails.Barcode IS NULL)) AND (ItemsUnitsDetails.Barcode<>'') AND (CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
		) AS Tbl

		END 
		ELSE 
		BEGIN
				INSERT INTO OSFA_DB.[dbo].[OT_ItemsUnitsBarcode]
				   ([CompNo]
				   ,[SalesmanNo]
				   ,[ItemCode]
				   ,[Unit]
				   ,[Barcode])
				SELECT DISTINCT * FROM(
				SELECT        Items.CompanyID, @SalesmanNo AS SalesmanNo, Items.ItemCode, dbo.trim( Items.UnitID) AS UnitID, 
		
				 case when @ClientActive=24 and @SalesmanNo>9989 then items.Reference3  else dbo.trim(Items.Barcode) end  AS Barcode
				FROM            Items INNER JOIN  
								OSFA_DB.dbo.OT_ItemsMF ON Items.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND Items.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
				WHERE         (NOT (Items.Barcode IS NULL)) AND (Items.Barcode<>'')  AND(Items.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)

				UNION ALL
				SELECT        CompanyID, @SalesmanNo AS SalesmanNo, ItemsUnitsDetails.ItemCode, dbo.trim( UnitID) AS UnitID, dbo.trim(ItemsUnitsDetails.Barcode) AS Barcode
				FROM            ItemsUnitsDetails  INNER JOIN  
								OSFA_DB.dbo.OT_ItemsMF ON ItemsUnitsDetails.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND ItemsUnitsDetails.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
				WHERE        (NOT (ItemsUnitsDetails.Barcode IS NULL)) AND (ItemsUnitsDetails.Barcode<>'') AND (CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
		) AS Tbl

		END
	END 
else IF @ClientActive = 161
BEGIN
	INSERT INTO OSFA_DB.[dbo].[OT_ItemsUnitsBarcode]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[ItemCode]
			   ,[Unit]
			   ,[Barcode])
	SELECT        CompanyID, @SalesmanNo, ItemCode, UnitID, Barcode
	FROM            ItemsBarcodes
	WHERE        (CompanyID = @CompNo)
END
ELSE
BEGIN 
	INSERT INTO OSFA_DB.[dbo].[OT_ItemsUnitsBarcode]
			   ([CompNo]
			   ,[SalesmanNo]
			   ,[ItemCode]
			   ,[Unit]
			   ,[Barcode])
		SELECT DISTINCT * FROM(
			SELECT        Items.CompanyID, @SalesmanNo AS SalesmanNo, Items.ItemCode, dbo.trim( Items.UnitID) AS UnitID, 
		
			 case when @ClientActive=24 and @SalesmanNo>9989 then items.Reference3  else dbo.trim(Items.Barcode) end  AS Barcode
			FROM            Items INNER JOIN  
							OSFA_DB.dbo.OT_ItemsMF ON Items.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND Items.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
			WHERE         (NOT (Items.Barcode IS NULL)) AND (Items.Barcode<>'')  AND(Items.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)

			UNION ALL
			SELECT        CompanyID, @SalesmanNo AS SalesmanNo, ItemsUnitsDetails.ItemCode, dbo.trim( UnitID) AS UnitID, dbo.trim(ItemsUnitsDetails.Barcode) AS Barcode
			FROM            ItemsUnitsDetails  INNER JOIN  
							OSFA_DB.dbo.OT_ItemsMF ON ItemsUnitsDetails.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND ItemsUnitsDetails.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
			WHERE        (NOT (ItemsUnitsDetails.Barcode IS NULL)) AND (ItemsUnitsDetails.Barcode<>'') AND (CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
	) AS Tbl
END 

--///////// OT_CustomersClasses----
if @clientactive=149
Begin
INSERT INTO [OSFA_DB].[dbo].[OT_CustomersClasses]
           ([CompNo]
		   ,[SalesmanNo]
           ,[Class_ID]
           ,[ArDesc]
           ,[EngDesc]
		   ,Ref1
		   ,Ref2
		   )
SELECT     CompanyID,@SalesmanNo, ID, Name AS Ar, Name AS En,Reference1,Reference2
FROM         locations
WHERE     (CompanyID = @CompNo) 
END
else 
begin


INSERT INTO [OSFA_DB].[dbo].[OT_CustomersClasses]
           ([CompNo]
		   ,[SalesmanNo]
           ,[Class_ID]
           ,[ArDesc]
           ,[EngDesc]
		   ,Ref1
		   ,Ref2
		   )
SELECT     CompanyID,@SalesmanNo, ID, Name AS Ar, Name AS En,Reference1,Reference2
FROM         CustomersClasses
WHERE     (CompanyID = @CompNo) 
END

 
SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_CustomersItemsAssigment, OT_ItemsUnitsBarcode, CustomersClasses [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

 --/////////////////// UPDATE Catalog Media ////////////////////////////////////////////////
SET @BeginTime = Convert(varchar(20),GetDate(),108)  

UPDATE       OSFA_DB.dbo.OT_ItemsMF
SET               PDFFileName=CatalogMedia.Name --+ '.pdf'
FROM            OSFA_DB.dbo.OT_ItemsMF INNER JOIN
                         Items ON OSFA_DB.dbo.OT_ItemsMF.CompNo = Items.CompanyID AND OSFA_DB.dbo.OT_ItemsMF.ItemNo = Items.ItemCode INNER JOIN
                         CatalogMedia ON Items.PDFFileID = CatalogMedia.AutoID 
WHERE        (OSFA_DB.dbo.OT_ItemsMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)


UPDATE       OSFA_DB.dbo.OT_ItemsMF
SET               VideoFileName=CatalogMedia_1.Name
FROM            OSFA_DB.dbo.OT_ItemsMF INNER JOIN
                         Items ON OSFA_DB.dbo.OT_ItemsMF.CompNo = Items.CompanyID AND OSFA_DB.dbo.OT_ItemsMF.ItemNo = Items.ItemCode INNER JOIN
                         CatalogMedia AS CatalogMedia_1 ON Items.VideoFileID = CatalogMedia_1.AutoID
WHERE        (OSFA_DB.dbo.OT_ItemsMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)


--/////////////////// OT_ItemsUnitsBarcode ////////////////////////////////////////////////


--SELECT       @IsMakeReturnOrder =  isnull (SalesPersonsDevicePermissions.AllowReturnOrder,0)
--FROM            SalesPersonsDevicePermissions INNER JOIN
--                         SalesPersons ON SalesPersonsDevicePermissions.CompanyID = SalesPersons.CompanyID AND SalesPersonsDevicePermissions.PositionsID = SalesPersons.PositionID
--						 where
--						SalesPersons.CompanyID=@CompNo and SalesPersons.ID=@SalesmanNo and  SalesPersonsDevicePermissions.AllowReturnOrder = 1
--Declare @SalesmanStore nvarchar(max)  
--select @SalesmanStore = SalesPersons.SerialRef from SalesPersons where CompanyID=@CompNo and ID=@SalesmanNo

 if @ClientActive=24
 Begin

SELECT @StoreID = Reference2 FROM olives_bo.dbo.SalesPersons WHERE (CompanyID = @CompNo) AND (ID = @SalesmanNo)

INSERT INTO OSFA_DB.dbo.OT_BatchsInfo
                         (CompNo, SalesmanNo, ItemNo, BatchNo, ExpireDate, Qty, Ref1, Ref2, BatchBarcode)

	SELECT        @CompNo AS companyID, @SalesmanNo,SAP_Integration.dbo.ItemsBatches.ItemNo, BatchID,  cast (year (ExpDate) as nvarchar (10))+'-'+cast (month (ExpDate) as nvarchar (10)) +'-'+
 cast (day (ExpDate) as nvarchar (10)) , Qty, UnitID,NULL,NULL
FROM            SAP_Integration.dbo.ItemsBatches   INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON @CompNo= OSFA_DB.dbo.OT_ItemsMF.CompNo AND SAP_Integration.dbo.ItemsBatches.ItemNo collate SQL_Latin1_General_CP1_CI_AS = OSFA_DB.dbo.OT_ItemsMF.ItemNo
where StoreID =@StoreID and OSFA_DB.dbo.OT_ItemsMF.CompNo=@CompNo  AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)

 End




  if @ClientActive = 123 
Begin
if  @SalesPersonType=7
Begin
	INSERT INTO OSFA_DB.dbo.OT_BatchsInfo
							 (CompNo, SalesmanNo, ItemNo, BatchNo, ExpireDate, Qty, BatchBarcode)
	SELECT        CompanyID, SalesPersonID, ItemCode, BatchNo, 1 AS Expr1, ItemQuantity,BatchNo
	FROM            SalesPersonItemsBalanceBatches
	WHERE        (SalesPersonItemsBalanceBatches.CompanyID = @CompNo) AND (SalesPersonItemsBalanceBatches.SalesPersonID = @SalesmanNo)
end
else
	Begin
	INSERT INTO OSFA_DB.dbo.OT_BatchsInfo
							 (CompNo, SalesmanNo, ItemNo, BatchNo, ExpireDate, Qty, Ref1, Ref2, BatchBarcode)

SELECT xbt.CompanyID, xbt.SalesmanNo, xbt.ItemNo, xbt.BatchNo, xbt.ExpireDate, SalesPersonItemsBalanceBatches.ItemQuantity, xbt.Ref1, xbt.Ref2, xbt.BatchBarcode
FROM     (SELECT BatchsItemsInfo.CompanyID, @SalesmanNo AS SalesmanNo, BatchsItemsInfo.ItemNo, BatchsItemsInfo.BatchNo, BatchsItemsInfo.ExpireDate, BatchsItemsInfo.Qty, BatchsItemsInfo.Ref1, BatchsItemsInfo.Ref2, 
                                    BatchsItemsInfo.BatchBarcode
                  FROM      BatchsItemsInfo INNER JOIN
                                    OSFA_DB.dbo.OT_ItemsMF ON BatchsItemsInfo.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND BatchsItemsInfo.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo
                  WHERE   (BatchsItemsInfo.CompanyID =@CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)) AS xbt INNER JOIN
                  SalesPersonItemsBalanceBatches ON xbt.CompanyID = SalesPersonItemsBalanceBatches.CompanyID AND xbt.SalesmanNo = SalesPersonItemsBalanceBatches.SalesPersonID AND 
                  xbt.ItemNo = SalesPersonItemsBalanceBatches.ItemCode AND xbt.BatchNo = SalesPersonItemsBalanceBatches.BatchNo
Union All
SELECT CompNo, SalesmanNo, ItemNo, BatchNo, date, Expr1, Expr2, Expr3, Expr4
FROM     (SELECT DISTINCT CompNo, @SalesmanNo AS SalesmanNo, ItemNo, BatchNo, GETDATE() AS date, 1 AS Expr1, NULL AS Expr2, NULL AS Expr3, NULL AS Expr4
                  FROM      InvoiceHistoryDF) AS xbt 	where BatchNo not  in
				  (select batchno from SalesPersonItemsBalanceBatches where CompanyID=@CompNo and SalesPersonItemsBalanceBatches.SalesPersonID=@SalesmanNo)
				  and BatchNo<>'1'


--SELECT xbt.CompanyID, xbt.SalesmanNo, xbt.ItemNo, xbt.BatchNo, xbt.ExpireDate, xbt.Qty, xbt.Ref1, xbt.Ref2, xbt.BatchBarcode
--FROM     (SELECT BatchsItemsInfo.CompanyID, @SalesmanNo AS SalesmanNo, BatchsItemsInfo.ItemNo, BatchsItemsInfo.BatchNo, BatchsItemsInfo.ExpireDate, BatchsItemsInfo.Qty, BatchsItemsInfo.Ref1, BatchsItemsInfo.Ref2, 
--                                    BatchsItemsInfo.BatchBarcode
--                  FROM      BatchsItemsInfo INNER JOIN
--                                    OSFA_DB.dbo.OT_ItemsMF ON BatchsItemsInfo.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND BatchsItemsInfo.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo
--                  WHERE   (BatchsItemsInfo.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)) AS xbt 
--				  INNER JOIN
--                      (SELECT distinct CompNo, ItemNo, BatchNo
--                       FROM      InvoiceHistoryDF) AS derivedtbl_1 ON xbt.CompanyID = derivedtbl_1.CompNo AND xbt.ItemNo = derivedtbl_1.ItemNo AND xbt.BatchNo = derivedtbl_1.BatchNo
--					   where xbt.BatchNo<>'1' 

	End


end

if @ClientActive =111 or @ClientActive =144 or @ClientActive=91
Begin 

	INSERT INTO OSFA_DB.dbo.OT_BatchsInfo
							 (CompNo, SalesmanNo, ItemNo, BatchNo, ExpireDate, Qty, Ref1, Ref2, BatchBarcode)
	SELECT        BatchsItemsInfo.CompanyID, @SalesmanNo AS SalesmanNo, BatchsItemsInfo.ItemNo, BatchsItemsInfo.BatchNo, BatchsItemsInfo.ExpireDate, BatchsItemsInfo.Qty, BatchsItemsInfo.Ref1, BatchsItemsInfo.Ref2, 
							 BatchsItemsInfo.BatchBarcode
	FROM            BatchsItemsInfo INNER JOIN
							 OSFA_DB.dbo.OT_ItemsMF ON BatchsItemsInfo.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND BatchsItemsInfo.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo
	WHERE        (BatchsItemsInfo.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)
end


				

IF @ClientActive=35

BEGIN 
select 0

/*
Remove the comment after update /* */

IF @IsMakeInoice=1
BEGIN 

Delete from OSFA_DB..[OT_BatchsInfo] where [CompNo]=@CompNo and [SalesmanNo]=@SalesmanNo

 


INSERT INTO OSFA_DB..[OT_BatchsInfo]
           ([CompNo]
           ,[SalesmanNo]
           ,[ItemNo]
           ,[BatchNo]
		   ,[Qty]
           ,[ExpireDate]
           
           )
		     
		     
		select distinct  CompanyID,ID ,ItemCode, LOTNUM, SUM (QTYLOT )  as QTYLOT , expirydate 
from (
SELECT     distinct     Items.CompanyID,SalesPersons.ID ,Items.ItemCode,Rtrim ( vstocklot.LOTNUM) as LOTNUM,vstocklot.QTYLOT 
,substring (cast (expirydate as nvarchar  ),1,4)+'-'+substring (cast (expirydate as nvarchar (10) ),5,2)+'-'+substring (cast (expirydate as nvarchar  ),7,2) as  expirydate

FROM            [LUX].[LUXintegratopn].dbo.vstocklot vstocklot INNER JOIN
                         [LUX].[LUXintegratopn].dbo.vSalesPerson vSalesPerson ON vstocklot.LOCATION = vSalesPerson.LOCATION INNER JOIN
                        Olives_BO.. Items ON vstocklot.Company = Items.Reference2 COLLATE SQL_Latin1_General_CP1_CI_AS AND 
                         vstocklot.ITEMNO = Items.Reference1 COLLATE Arabic_100_CI_AS_KS INNER JOIN
                        Olives_BO.. ItemsUnits ON vstocklot.Company = ItemsUnits.Reference2 COLLATE SQL_Latin1_General_CP1_CI_AS AND 
                         vstocklot.COSTUNIT = ItemsUnits.Reference1 COLLATE Arabic_100_CI_AS_KS INNER JOIN
                        Olives_BO.. SalesPersons ON vSalesPerson.CODESLSP = SalesPersons.Reference1 COLLATE Arabic_100_CI_AS_KS AND 
                         vstocklot.LOCATION = SalesPersons.DeviceID COLLATE Arabic_100_CI_AS_KS
WHERE        --(vstocklot.QTYLOT > 0) AND 
(SalesPersons.ID = @SalesmanNo) AND   (Items.CompanyID = @CompNo)
and LOTNUM is not null 
						 

-- and ItemCode='1-BVOCE000020'  
-- and LOTNUM= '00000003'
/*
UNION all 

SELECT     distinct    Items.CompanyID,@SalesmanNo,Items.ItemCode,  cds_integration.dbo.vstocklot.LOTNUM,0 as QTYLOT 
,substring (cast (expirydate as nvarchar  ),1,4)+'-'+substring (cast (expirydate as nvarchar (10) ),5,2)+'-'+substring (cast (expirydate as nvarchar  ),7,2) as expirydate

FROM            cds_integration.dbo.vstocklot INNER JOIN
                         cds_integration.dbo.vSalesPerson ON cds_integration.dbo.vstocklot.LOCATION = cds_integration.dbo.vSalesPerson.LOCATION INNER JOIN
                        Olives_BO.. Items ON cds_integration.dbo.vstocklot.Company = Items.Reference2 COLLATE SQL_Latin1_General_CP1_CI_AS AND 
                         cds_integration.dbo.vstocklot.ITEMNO = Items.Reference1 COLLATE Arabic_100_CI_AS_KS INNER JOIN
                        Olives_BO.. ItemsUnits ON cds_integration.dbo.vstocklot.Company = ItemsUnits.Reference2 COLLATE SQL_Latin1_General_CP1_CI_AS AND 
                         cds_integration.dbo.vstocklot.COSTUNIT = ItemsUnits.Reference1 COLLATE Arabic_100_CI_AS_KS INNER JOIN
                        Olives_BO.. SalesPersons ON cds_integration.dbo.vSalesPerson.CODESLSP = SalesPersons.Reference1 COLLATE Arabic_100_CI_AS_KS 
WHERE        (SalesPersons.ID <>@SalesmanNo) AND   (Items.CompanyID = @CompNo) 
and LOTNUM is not null --  and ItemCode='1-BVOCE000020' 
*/
) TTT
group by CompanyID,ID ,ItemCode, LOTNUM,  expirydate 
END

ELSE 
BEGIN 
print'ssssss'
Delete from OSFA_DB..[OT_BatchsInfo] where [CompNo]=@CompNo and [SalesmanNo]=@SalesmanNo

INSERT INTO OSFA_DB..[OT_BatchsInfo]
           ([CompNo]
           ,[SalesmanNo]
           ,[ItemNo]
           ,[BatchNo]
		   ,[Qty]
           ,[ExpireDate]
           
           )
		     
		select distinct  CompanyID,ID ,ItemCode, LOTNUM, SUM (QTYLOT )  as QTYLOT , expirydate 
from (


SELECT     distinct     Items.CompanyID,@SalesmanNo as ID ,Items.ItemCode, Rtrim ( vstocklot.LOTNUM) as LOTNUM,vstocklot.QTYLOT 
,substring (cast (expirydate as nvarchar  ),1,4)+'-'+substring (cast (expirydate as nvarchar (10) ),5,2)+'-'+substring (cast (expirydate as nvarchar  ),7,2) as  expirydate

FROM            [LUX].[LUXintegratopn].dbo.vstocklot  vstocklot INNER JOIN
                         
                        Olives_BO.. Items ON vstocklot.Company = Items.Reference2 COLLATE SQL_Latin1_General_CP1_CI_AS
						AND 
                         vstocklot.ITEMNO = Items.Reference1 COLLATE Arabic_100_CI_AS_KS 
						 INNER JOIN
                        Olives_BO.. ItemsUnits ON vstocklot.Company = ItemsUnits.Reference2 COLLATE SQL_Latin1_General_CP1_CI_AS AND 
                         vstocklot.COSTUNIT = ItemsUnits.Reference1 COLLATE Arabic_100_CI_AS_KS				             
WHERE         (Items.CompanyID = @CompNo)and LOTNUM is not null and  LOCATION='008'

-- and ItemCode='1-BVOCE000020'  

-- and LOTNUM= '00000003'
/*
UNION all 

SELECT     distinct    Items.CompanyID,@SalesmanNo,Items.ItemCode,  cds_integration.dbo.vstocklot.LOTNUM,0 as QTYLOT 
,substring (cast (expirydate as nvarchar  ),1,4)+'-'+substring (cast (expirydate as nvarchar (10) ),5,2)+'-'+substring (cast (expirydate as nvarchar  ),7,2) as expirydate

FROM            cds_integration.dbo.vstocklot INNER JOIN
                         cds_integration.dbo.vSalesPerson ON cds_integration.dbo.vstocklot.LOCATION = cds_integration.dbo.vSalesPerson.LOCATION INNER JOIN
                        Olives_BO.. Items ON cds_integration.dbo.vstocklot.Company = Items.Reference2 COLLATE SQL_Latin1_General_CP1_CI_AS AND 
                         cds_integration.dbo.vstocklot.ITEMNO = Items.Reference1 COLLATE Arabic_100_CI_AS_KS INNER JOIN
                        Olives_BO.. ItemsUnits ON cds_integration.dbo.vstocklot.Company = ItemsUnits.Reference2 COLLATE SQL_Latin1_General_CP1_CI_AS AND 
                         cds_integration.dbo.vstocklot.COSTUNIT = ItemsUnits.Reference1 COLLATE Arabic_100_CI_AS_KS INNER JOIN
                        Olives_BO.. SalesPersons ON cds_integration.dbo.vSalesPerson.CODESLSP = SalesPersons.Reference1 COLLATE Arabic_100_CI_AS_KS 
WHERE        (SalesPersons.ID <>@SalesmanNo) AND   (Items.CompanyID = @CompNo)
and LOTNUM is not null --  and ItemCode='1-BVOCE000020' 
*/
) TTT
group by CompanyID,ID ,ItemCode, LOTNUM,  expirydate 
END 

*/
END 



else if @ClientActive=82 or @ClientActive=0
Begin
Select '82'
INSERT INTO OSFA_DB.dbo.OT_BatchsInfo
                         (CompNo, SalesmanNo, ItemNo, BatchNo, ExpireDate, Qty, Ref1, Ref2, BatchBarcode)
SELECT        BatchsItemsInfo.CompanyID, @SalesmanNo AS SalesmanNo, BatchsItemsInfo.ItemNo, BatchsItemsInfo.BatchNo, BatchsItemsInfo.ExpireDate, BatchsItemsInfo.Qty, BatchsItemsInfo.Ref1, BatchsItemsInfo.Ref2, 
                         BatchsItemsInfo.BatchBarcode
FROM            BatchsItemsInfo INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON BatchsItemsInfo.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND BatchsItemsInfo.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo
WHERE        (BatchsItemsInfo.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo)

END
ELSE
BEGIN
	INSERT INTO OSFA_DB.dbo.OT_BatchsInfo (CompNo, SalesmanNo, ItemNo, BatchNo, ExpireDate, Qty, Ref1, Ref2, BatchBarcode)
	SELECT   CompanyID, @SalesmanNo AS SalesmanNo, ItemNo, BatchNo, ExpireDate, Qty, Ref1, Ref2, BatchBarcode
	FROM         BatchsItemsInfo
	WHERE     (CompanyID = @CompNo)
END



SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Updat PDFFileName, VideoFileName in OT_ItemsMF, OT_BatchsInfo [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')



SET @BeginTime = Convert(varchar(20),GetDate(),108)
--/////////////////// OT_CustomersGPSLocations ////////////////////////////////////////////////

If @ClientActive = 85
BEGIN
	DECLARE @TodayRouteID int
	SELECT @TodayRouteID =ISNULL([RouteID],0)  FROM [OSFA_DB].[dbo].[OT_SalesmanRoute]   
	WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND [RouteDate]=CAST(GETDATE() AS DATE)

	INSERT INTO [OSFA_DB].[dbo].[OT_CustomersGPSLocations]
			   ([CompanyID]
			   ,[SalesmanNo]
			   ,[CustomerID]
			   ,[GPSX]
			   ,[GPSY]
			   ,[Notes]
			   ,[Loc_Address],LineID)
	SELECT DISTINCT 
                         CustomersGPSLocations.CompanyID, @SalesmanNo AS Expr1, CustomersGPSLocations.CustomerID, CustomersGPSLocations.GPSX, CustomersGPSLocations.GPSY, CASE WHEN CustomersFinancialDetails.CompanyID IS NULL THEN '' ELSE 'TodayRoute' END, 
                         CustomersGPSLocations.Loc_Address, CustomersGPSLocations.LineID
	FROM            OSFA_DB.dbo.OT_CustomerMF INNER JOIN
                         CustomersGPSLocations ON OSFA_DB.dbo.OT_CustomerMF.CompNo = CustomersGPSLocations.CompanyID AND OSFA_DB.dbo.OT_CustomerMF.CustomerNo = CustomersGPSLocations.CustomerID LEFT OUTER JOIN
                         CustomersFinancialDetails ON CustomersGPSLocations.CompanyID = CustomersFinancialDetails.CompanyID AND CustomersGPSLocations.CustomerID = CustomersFinancialDetails.CustomerID AND 
                         CustomersGPSLocations.LineID = CustomersFinancialDetails.LocationLineID AND (CustomersFinancialDetails.RouteID = @TodayRouteID OR @TodayRouteID=0) AND 
							 (CustomersFinancialDetails.PositionsID = @PositionsID) 
	WHERE        (OSFA_DB.dbo.OT_CustomerMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 

END
ELSE
BEGIN
	INSERT INTO [OSFA_DB].[dbo].[OT_CustomersGPSLocations]
			   ([CompanyID]
			   ,[SalesmanNo]
			   ,[CustomerID]
			   ,[GPSX]
			   ,[GPSY]
			   ,[Notes]
			   ,[Loc_Address],LineID)
	SELECT [CompanyID]
			   ,@SalesmanNo
			   ,[CustomerID]
			   ,[GPSX]
			   ,[GPSY]
			   ,CustomersGPSLocations.[Notes]
			   ,CustomersGPSLocations.[Loc_Address],LineID
	FROM OSFA_DB.dbo.OT_CustomerMF INNER JOIN
	CustomersGPSLocations ON OSFA_DB.dbo.OT_CustomerMF.CompNo = CustomersGPSLocations.CompanyID AND
	OSFA_DB.dbo.OT_CustomerMF.CustomerNo = CustomersGPSLocations.CustomerID
	WHERE (OSFA_DB.dbo.OT_CustomerMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 
END



SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_CustomersGPSLocations [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')




If @ClientActive=11 and @IsMakeOrder=1 -- Tower2
begin


INSERT INTO OSFA_DB.dbo.OT_StoreItemsQty
                         (CompNo, StoreNo, ItemNo, Qty)
SELECT        OSFA_DB.dbo.OT_ItemsMF.CompNo, @SalesmanNo AS Expr1, OSFA_DB.dbo.OT_ItemsMF.ItemNo, OSFA_DB.dbo.OT_ItemsMF.QtyOH
FROM            OSFA_DB.dbo.OT_ItemsMF LEFT OUTER JOIN
                         OSFA_DB.dbo.OT_StoreItemsQty ON OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = OSFA_DB.dbo.OT_StoreItemsQty.StoreNo AND OSFA_DB.dbo.OT_ItemsMF.ItemNo = OSFA_DB.dbo.OT_StoreItemsQty.ItemNo AND 
                         OSFA_DB.dbo.OT_ItemsMF.CompNo = OSFA_DB.dbo.OT_StoreItemsQty.CompNo
WHERE        (OSFA_DB.dbo.OT_ItemsMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_StoreItemsQty.CompNo IS NULL)

end


--IF @ClientActive=36 ----- AmanaFood 
--BEGIN

--	INSERT INTO [OSFA_DB].[dbo].[OT_StoreItemsQty]
--			   ([CompNo]
--			   ,[StoreNo]
--			   ,[ItemNo]
--			   ,[Qty])
--	SELECT        @CompNo AS Expr1, @SalesmanNo AS Expr2, OSFA_DB.dbo.OT_ItemsMF.ItemNo, 10000 AS Expr3
--	FROM            OSFA_DB.dbo.OT_ItemsMF LEFT OUTER JOIN
--							 OSFA_DB.dbo.OT_StoreItemsQty ON OSFA_DB.dbo.OT_ItemsMF.CompNo = OSFA_DB.dbo.OT_StoreItemsQty.CompNo AND 
--							 OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = OSFA_DB.dbo.OT_StoreItemsQty.StoreNo AND OSFA_DB.dbo.OT_ItemsMF.ItemNo = OSFA_DB.dbo.OT_StoreItemsQty.ItemNo
--	WHERE        (OSFA_DB.dbo.OT_ItemsMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_ItemsMF.Ref5 = 'Additional_Item') AND 
--							 (OSFA_DB.dbo.OT_StoreItemsQty.CompNo IS NULL)



--	UPDATE       OSFA_DB.dbo.OT_StoreItemsQty
--	SET                Qty = 10000
--	FROM            OSFA_DB.dbo.OT_ItemsMF INNER JOIN
--							 OSFA_DB.dbo.OT_StoreItemsQty ON OSFA_DB.dbo.OT_ItemsMF.CompNo = OSFA_DB.dbo.OT_StoreItemsQty.CompNo AND 
--							 OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = OSFA_DB.dbo.OT_StoreItemsQty.StoreNo AND OSFA_DB.dbo.OT_ItemsMF.ItemNo = OSFA_DB.dbo.OT_StoreItemsQty.ItemNo
--	WHERE        (OSFA_DB.dbo.OT_ItemsMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo) AND (OSFA_DB.dbo.OT_ItemsMF.Ref5 = 'Additional_Item')


--END




	
--IF @ClientActive=30 ----- Zumot 
--BEGIN
--	EXEC GP_Integ_GetCreditInvoice_Zumot @CompNo,@SalesmanNo

--END


IF @ClientActive=36
BEGIN
	UPDATE       OSFA_DB.dbo.OT_CustomerMF
	SET                CustomerRef1 = Customers.Account, CustomerRef3 = Customers.POBox,FullAddress=Address+'-'+Locations.Name
	FROM            OSFA_DB.dbo.OT_CustomerMF INNER JOIN
							 Customers ON OSFA_DB.dbo.OT_CustomerMF.CompNo = Customers.CompanyID AND OSFA_DB.dbo.OT_CustomerMF.CustomerNo = Customers.ID INNER JOIN
							 Locations ON Customers.CompanyID = Locations.CompanyID AND Customers.LocationID = Locations.ID
	WHERE        (OSFA_DB.dbo.OT_CustomerMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 
END


--///////// TakedSurveyIDs ////////////////////

SET @BeginTime = Convert(varchar(20),GetDate(),108)

DECLARE @SurveyDate smalldatetime
SET @SurveyDate = DATEADD(M,-1, @SendDate)

UPDATE OSFA_DB.dbo.OT_CustomerMF SET TakedSurveyIDs=IDs
FROM OSFA_DB.dbo.OT_CustomerMF INNER JOIN (
SELECT    DISTINCT    CompanyID, Customer_No,  STUFF((SELECT DISTINCT ';' + CAST(A.Survey_ID AS VARCHAR) FROM SurveyCustomers A
Where A.CompanyID=B.CompanyID AND A.Customer_No=B.Customer_No AND (A.Survey_Date >=@SurveyDate) FOR XML PATH('')),1,1,'') As IDs
FROM            SurveyCustomers B INNER JOIN OSFA_DB.dbo.OT_CustomerMF  ON OSFA_DB.dbo.OT_CustomerMF.CompNo = B.CompanyID AND OSFA_DB.dbo.OT_CustomerMF.CustomerNo = B.Customer_No
WHERE     (Survey_Date >=@SurveyDate)  AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 
GROUP BY CompanyID,  Customer_No
HAVING        (CompanyID = @CompNo) )AS CalcTbl
ON CalcTbl.CompanyID=OSFA_DB.dbo.OT_CustomerMF.CompNo AND CalcTbl.Customer_No=OSFA_DB.dbo.OT_CustomerMF.CustomerNo
WHERE        (OSFA_DB.dbo.OT_CustomerMF.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) 

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Update TakedSurveyIDs In OT_CustomerMF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

IF @ClientActive <> 27 and @ClientActive <>136 and @ClientActive >67  and @ClientActive <>165
BEGIN
SET @BeginTime = Convert(varchar(20),GetDate(),108)

UPDATE       OSFA_DB.dbo.OT_CustomerMF
SET                CustTargetTot = Fun_GetCustomersTargetAndSales_1.TargetAmount, CustSalesTot = Fun_GetCustomersTargetAndSales_1.NetSalesAmount
FROM            dbo.Fun_GetCustomersTargetAndSales(@CompNo, @Year, @FromMonth, @ToMonth) AS Fun_GetCustomersTargetAndSales_1 INNER JOIN
                         OSFA_DB.dbo.OT_CustomerMF ON Fun_GetCustomersTargetAndSales_1.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND 
                         Fun_GetCustomersTargetAndSales_1.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo
WHERE        (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Update CustTargetTot, CustSalesTot In OT_CustomerMF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')
END

SET @BeginTime = Convert(varchar(20),GetDate(),108)

--INSERT INTO OSFA_DB.dbo.OT_CustIssueAmount (CompNo, SalesmanNo, OrderYear, OrderNo, CustID, OrderDate, Amount, Notes)
--SELECT        PaymentsOrders.CompanyID, @SalesmanNo AS SalesmanNo, PaymentsOrders.OrderYear, PaymentsOrders.OrderNo, PaymentsOrders.CustomerID, PaymentsOrders.OrderDate, PaymentsOrders.Amount, '' AS Notes
--FROM            PaymentsOrders INNER JOIN
--                         OSFA_DB.dbo.OT_CustomerMF ON PaymentsOrders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND PaymentsOrders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND 
--                         PaymentsOrders.SalespersonID = OSFA_DB.dbo.OT_CustomerMF.SalesmanNo
--WHERE        (PaymentsOrders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (PaymentsOrders.IsSuspended = 0)  AND (ISNULL(PaymentsOrders.IsSuspended,0) = 0)  AND (ISNULL(PaymentsOrders.IsIssued,0) = 0) 

INSERT INTO OSFA_DB.dbo.OT_CustIssueAmount (CompNo, SalesmanNo, OrderYear, OrderNo, CustID, OrderDate, Amount, Notes)
SELECT        PaymentsOrders.CompanyID, @SalesmanNo AS SalesmanNo, PaymentsOrders.OrderYear, PaymentsOrders.OrderNo, PaymentsOrders.CustomerID, PaymentsOrders.OrderDate, PaymentsOrders.Amount, '' AS Notes
FROM            PaymentsOrders INNER JOIN
                         OSFA_DB.dbo.OT_CustomerMF ON PaymentsOrders.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND PaymentsOrders.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo AND 
                         PaymentsOrders.SalespersonID = OSFA_DB.dbo.OT_CustomerMF.SalesmanNo
WHERE        (PaymentsOrders.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (CAST(PaymentsOrders.OrderDate AS DATE) = CAST(GETDATE() AS DATE)) AND (PaymentsOrders.IsSuspended = 0)  AND (ISNULL(PaymentsOrders.IsSuspended,0) = 0)  AND (ISNULL(PaymentsOrders.IsIssued,0) = 1) 


INSERT INTO OSFA_DB.dbo.OT_ReturnChecks (CompNo, SalesmanNo, CustomerNo, TransType, TransYear, TransNo, BankNo, BranchNo, CheckNo, Amount, RemainingAmount, DueDate, TransDate, Ref1, Ref2, Ref3, Ref4)
SELECT        Checks.CompanyID, OSFA_DB.dbo.OT_CustomerMF.SalesmanNo, Checks.CustomerID, Checks.TransactionTypeID, Checks.TransactionYear, Checks.TransactionNo, Checks.BankID, Checks.BranchID, Checks.ChequeNo, 
                         Checks.Amount, Checks.Amount - ISNULL(SUM(Receipts_PaidTransChecks.PaidAmount),0) AS RemAmount, Checks.DueDate, Receipts.TransactionDate, '' AS Expr1, '' AS Expr2, '' AS Expr3, '' AS Expr4
FROM            Checks INNER JOIN
                         OSFA_DB.dbo.OT_CustomerMF ON Checks.CompanyID = OSFA_DB.dbo.OT_CustomerMF.CompNo AND Checks.CustomerID = OSFA_DB.dbo.OT_CustomerMF.CustomerNo INNER JOIN
                         Receipts ON Checks.CompanyID = Receipts.CompanyID AND Checks.TransactionTypeID = Receipts.TransactionTypeID AND Checks.TransactionNo = Receipts.TransactionNo AND 
                         Checks.TransactionYear = Receipts.TransactionYear LEFT OUTER JOIN
                         Receipts_PaidTransChecks ON Checks.CompanyID = Receipts_PaidTransChecks.CompanyID AND Checks.BankID = Receipts_PaidTransChecks.PaidTransBankID AND 
                         Checks.BranchID = Receipts_PaidTransChecks.PaidTransBranchID AND Checks.TransactionYear = Receipts_PaidTransChecks.PaidTransYear AND Checks.TransactionNo = Receipts_PaidTransChecks.PaidTransNo AND 
                         Checks.TransactionTypeID = Receipts_PaidTransChecks.PaidTransTypeID AND Checks.CustomerID = Receipts_PaidTransChecks.PaidTransCustomerID AND 
                         Checks.ChequeNo = Receipts_PaidTransChecks.PaidTransChequeNo
WHERE         (Checks.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo) AND (ISNULL(Checks.CheckStatus, 0) = 1)
GROUP BY Checks.CompanyID, OSFA_DB.dbo.OT_CustomerMF.SalesmanNo, Checks.CustomerID, Checks.TransactionTypeID, Checks.TransactionYear, Checks.TransactionNo, Checks.BankID, Checks.BranchID, Checks.ChequeNo, 
                         Checks.Amount, Checks.DueDate, Receipts.TransactionDate   
HAVING  Checks.Amount - ISNULL(SUM(Receipts_PaidTransChecks.PaidAmount),0) > 0
						   
--UPDATE    OSFA_DB.dbo.OT_StoreItemsQty
--SET              Qty = ROUND(Qty,0)
--FROM         OSFA_DB.dbo.OT_StoreItemsQty INNER JOIN
--                      OSFA_DB.dbo.OT_ItemsMF ON OSFA_DB.dbo.OT_StoreItemsQty.CompNo = OSFA_DB.dbo.OT_ItemsMF.CompNo AND 
--                      OSFA_DB.dbo.OT_StoreItemsQty.ItemNo = OSFA_DB.dbo.OT_ItemsMF.ItemNo
--WHERE     (OSFA_DB.dbo.OT_StoreItemsQty.CompNo = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo) AND 
--                      (OSFA_DB.dbo.OT_StoreItemsQty.StoreNo = @SalesmanNo)


INSERT INTO [OSFA_DB].[dbo].[OT_ItemsSalesUnits]
           ([CompanyID]
           ,[SalesmanNo]
           ,[ItemCode]
           ,[UnitCode]
           ,[Reference1]
           ,[Reference2])

SELECT        SalesPersonItemsSalesUnits.CompanyID, @SalesmanNo AS SalesmanNo, SalesPersonItemsSalesUnits.ItemCode, SalesPersonItemsSalesUnits.UnitCode,SalesPersonItemsSalesUnits.[Reference1], SalesPersonItemsSalesUnits.[Reference2]
FROM            SalesPersonItemsSalesUnits INNER JOIN
                         OSFA_DB.dbo.OT_ItemsMF ON SalesPersonItemsSalesUnits.CompanyID = OSFA_DB.dbo.OT_ItemsMF.CompNo AND SalesPersonItemsSalesUnits.ItemCode = OSFA_DB.dbo.OT_ItemsMF.ItemNo
WHERE        (SalesPersonItemsSalesUnits.CompanyID = @CompNo) AND (OSFA_DB.dbo.OT_ItemsMF.SalesmanNo = @SalesmanNo) AND SalesPersonItemsSalesUnits.PositionsID=@PositionsID


SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_CustIssueAmount, OT_ReturnChecks, OT_ItemsSalesUnits [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')


SET @BeginTime = Convert(varchar(20),GetDate(),108)

IF @ClientActive = 16 --OR @ClientActive = 0  --ÊáÛÑÇÝ
BEGIN

	UPDATE       OSFA_DB.dbo.OT_CustomerMF
	SET                VisitActivityInOrder =  CASE WHEN OT_CustGalaryImages.[CustomerNo] IS NULL  AND ISNULL(OT_CustomerMF.IsSuspended,0)=0  THEN 'PlanogramsImages' ELSE '' END
	FROM            OSFA_DB.dbo.OT_CustomerMF AS OT_CustomerMF LEFT OUTER JOIN
							OSFA_DB..OT_CustGalaryImages AS OT_CustGalaryImages ON OT_CustomerMF.CompNo = OT_CustGalaryImages.CompNo AND OT_CustomerMF.CustomerNo = OT_CustGalaryImages.[CustomerNo] AND OT_CustGalaryImages.PlanogramFileAutoID=1 
	WHERE        (OT_CustomerMF.CompNo = @CompNo)  AND (OT_CustomerMF.SalesmanNo = @SalesmanNo)


END
ELSE
BEGIN

	UPDATE       OSFA_DB.dbo.OT_CustomerMF
	SET                VisitActivityInOrder =  CustomersVisitActivity.VisitActivityInOrder
	FROM            OSFA_DB.dbo.OT_CustomerMF INNER JOIN
							 CustomersVisitActivity ON OSFA_DB.dbo.OT_CustomerMF.CompNo = CustomersVisitActivity.CompanyID AND OSFA_DB.dbo.OT_CustomerMF.CustomerNo = CustomersVisitActivity.CustomerID
	WHERE        (CustomersVisitActivity.CompanyID = @CompNo) AND (CustomersVisitActivity.PositionsID = @PositionsID)  AND (OSFA_DB.dbo.OT_CustomerMF.SalesmanNo = @SalesmanNo)


END

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Update  VisitActivityInOrder In OT_CustomerMF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')


SET @BeginTime = Convert(varchar(20),GetDate(),108)

if @SerialType = 1 --Serial By Notebooks
BEGIN
INSERT INTO [OSFA_DB].[dbo].[OT_SalesmanMF]
           ([CompNo]
           ,[SalesmanNo]
           ,[ArbSalesmanName]
           ,[EngSalesmanName]
           ,[Password]
           ,[Active]
           ,[NextSerial]
           ,[InvNextSerial]
           ,[RetInvNextSerial]
           ,[RecNextSerial]
           ,[StoreNo]
           ,[UseDefaultUnit]
           ,[AllowChangePrice]
           ,[AllowSales]
           ,[AllowReturnSales]
           ,[AllowOrder]
           ,[AllowRec]
           ,[AllowCons]
           ,[ConsNextSerial]
           ,[SalesmanGroup_ID]
           ,[AllowCustStock]
           ,[CustStockNextSerial]
           ,[AllowChangeOrderStore]
           ,[AllowChangeOrderBusUnit]
           ,[AllowChangeOrderDocType]
           ,[AllowChangeOrderCustName]
           ,[AllowMakeBonus]
           ,[AllowAddCust]
           ,[AllowGetCustGPS]
           ,[AllowItemDisc]
           ,[AllowVouDisc]
           ,[UseMultiStoreInSales]
           ,[AllowedVoidInvCount]
           ,[DayOff]
           ,[VouDiscLimit]
           ,[MinTotalOfSalesVou]
		   ,[CheckCreditLimitInOrder]
		   ,[CompetitiveItemsInfoNextSerial]
		   ,[SupervisorNo]
		   ,[SupervisorName]
		   ,[SupervisorTel]
		   ,[CompanyBrancheID]
		   ,[UnLoadOrdersNextSerials]
		   ,[CreditLimit]
		   ,[SalesmanBalance]
		   ,[AllowAddDrawer]
		   ,[MaxDiscountPerc]
		   ,[SalesmanStockNextSerial]
		   ,[AllowReturnOrder]
		   ,[ReturnOrderNextSerial]
		   ,[VanTransferNextSerial]
		   ,AllowVanTransfer
		   ,AutoSendData
		   ,AllowSalesQuotation 
		   ,SalesQuotationNextSerial
		   ,AllowItemsReplacment
		   ,ItemsReplacmentNextSerial
		   ,UserName
		   ,AllowAddProspectiveCust
		   ,SalesmanTel
		   ,AllowChangePriceInReturn
		   ,AllowItemDiscInReturn 
		   ,AllowVouDiscInReturn 
		   ,AllowUnloadOrder,AllowMakeIssueItems,MaxLoadOrderAmount,DebitCreditNoteNextSerial,AllowDebitCreditNote,ReceiveItemsNextSerial,CashOnHand,PaymentsOrdersNextSerial)
			SELECT        SalesPersons.CompanyID, SalesPersons.ID, SalesPersons.Name, 
						(CASE WHEN @ClientActive = 19 THEN SalesPersons.Reference1 ELSE CASE WHEN @ClientActive = 30 THEN CAST(SalesPersons.ID AS Varchar(10)) ELSE SalesPersons.Name END END) AS Eng, 
						 SalesPersonsDevicePermissions.Password, 1 AS Active, SalesPersonTransactionsSerials.OrderTakingNextSerial, 
									 SalesPersonTransactionsSerials.SalesInvoiceNextSerial, SalesPersonTransactionsSerials.ReturnSalesNextSerial, SalesPersonTransactionsSerials.ReceiptNextSerial, SalesPersons.ID AS Store, 
									 SalesPersonsDevicePermissions.UseDefaultUnit, SalesPersonsDevicePermissions.ChangePrice, SalesPersonsDevicePermissions.MakeSalesInvoice, SalesPersonsDevicePermissions.MakeReturnSales, 
									 SalesPersonsDevicePermissions.MakeOrderTaking, SalesPersonsDevicePermissions.MakeReceipt, SalesPersonsDevicePermissions.MakeTransferOrder, 
									 SalesPersonTransactionsSerials.TransferOrderNextSerial, SalesPersons.GroupID AS SalesmanGroup_ID, SalesPersonsDevicePermissions.AllowCustStock, SalesPersonTransactionsSerials.CustStockNextSerial, 
									 SalesPersonsDevicePermissions.AllowChangeOrderStore, SalesPersonsDevicePermissions.AllowChangeOrderBusUnit, SalesPersonsDevicePermissions.AllowChangeOrderDocType, 
									 SalesPersonsDevicePermissions.AllowChangeOrderCustName, SalesPersonsDevicePermissions.AllowMakeBonus, SalesPersonsDevicePermissions.AllowAddCust, 
									 SalesPersonsDevicePermissions.AllowGetCustGPS, SalesPersonsDevicePermissions.AllowItemDisc, SalesPersonsDevicePermissions.AllowVouDisc, SalesPersonsDevicePermissions.UseMultiStoreInSales, 
									 SalesPersonsDevicePermissions.CanceledInvoiceNo, ISNULL(SalesPersons.DayOff, 0) AS Expr1, SalesPersonsDevicePermissions.VouDiscLimit, SalesPersonsDevicePermissions.MinTotalOfSalesVou, 
									 SalesPersonsDevicePermissions.CheckCreditLimitInOrder, SalesPersonTransactionsSerials.CompetitiveItemsInfoNextSerial, @SupervisorNo AS Expr2, @SupervisorName AS Expr3, @SupervisorTel AS Expr4, 
									 SalesPersons.CompanyBrancheID, SalesPersonTransactionsSerials.UnLoadOrdersNextSerials, SalesPersons.CreditLimit, 0 AS SalesmanBalance, SalesPersonsDevicePermissions.AllowAddDrawer, 
									 SalesPersonsDevicePermissions.MaxDiscountPerc, SalesPersonTransactionsSerials.SalesmanStockNextSerial, SalesPersonsDevicePermissions.AllowReturnOrder, 
									 SalesPersonTransactionsSerials.ReturnOrderNextSerial, ISNULL(SalesPersonTransactionsSerials.VanTransferNextSerial, 0) AS Expr5, ISNULL(SalesPersonsDevicePermissions.AllowVanTransfer, 0) AS Expr6, 
									 ISNULL(SalesPersons.AutoSendData, 0) AS Expr7, ISNULL(SalesPersonsDevicePermissions.AllowSalesQuotation, 0) AS AllowSalesQuotation, ISNULL(SalesPersonTransactionsSerials.SalesQuotationNextSerial, 
									 0) AS SalesQuotationNextSerial, ISNULL(SalesPersonsDevicePermissions.AllowItemsReplacement, 0) AS AllowItemsReplacment, ISNULL(SalesPersonTransactionsSerials.ItemsReplacementNextSerial, 0) 
									 AS ItemsReplacmentNextSerial, SalespersonsSecurity.UserID, SalesPersonsDevicePermissions.AllowAddProspectiveCustomer, SalesPersons.TelephoneNo,ISNULL(AllowChangePriceInReturn,0) AS AllowChangePriceInReturn, AllowItemDiscInReturn ,AllowVouDiscInReturn,AllowUnloadOrder ,AllowMakeIssueItems,ISNULL(MaxLoadOrderAmount,0) AS MaxLoadOrderAmount,
									 DebitCreditNoteNextSerial,AllowDebitCreditNote,ReceiveItemsNextSerial,1000,PaymentsOrdersNextSerial
			FROM            SalesPersons INNER JOIN						
									 SalesPersonsGroups ON SalesPersons.GroupID = SalesPersonsGroups.ID AND SalesPersons.CompanyID = SalesPersonsGroups.CompanyID INNER JOIN
									 SalesPersonsDevicePermissions ON SalesPersons.CompanyID = SalesPersonsDevicePermissions.CompanyID AND SalesPersons.PositionID = SalesPersonsDevicePermissions.PositionsID LEFT OUTER JOIN
									 SalespersonsSecurity ON SalesPersons.CompanyID = SalespersonsSecurity.CompanyID AND SalesPersons.ID = SalespersonsSecurity.SalespersonID LEFT OUTER JOIN
									 SalesPersonTransactionsSerials ON SalesPersons.CompanyID = SalesPersonTransactionsSerials.CompanyID AND SalesPersons.ID = SalesPersonTransactionsSerials.SalesPersonID
			WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo) AND (SalesPersonTransactionsSerials.SerYear = YEAR(@SendDate))
END 
ELSE
BEGIN
select 'ADD'
-- Serial By Salesman

if @ClientActive=118 or @ClientActive =146
Begin
INSERT INTO [OSFA_DB].[dbo].[OT_SalesmanMF] 
           ([CompNo]
           ,[SalesmanNo]
           ,[ArbSalesmanName]
           ,[EngSalesmanName]
           ,[Password]
           ,[Active]
           ,[NextSerial]
           ,[InvNextSerial]
           ,[RetInvNextSerial]
           ,[RecNextSerial]
           ,[StoreNo]
           ,[UseDefaultUnit]
           ,[AllowChangePrice]
           ,[AllowSales]
           ,[AllowReturnSales]
           ,[AllowOrder]
           ,[AllowRec]
           ,[AllowCons]
           ,[ConsNextSerial]
           ,[SalesmanGroup_ID]
           ,[AllowCustStock]
           ,[CustStockNextSerial]
           ,[AllowChangeOrderStore]
           ,[AllowChangeOrderBusUnit]
           ,[AllowChangeOrderDocType]
           ,[AllowChangeOrderCustName]
           ,[AllowMakeBonus]
           ,[AllowAddCust]
           ,[AllowGetCustGPS]
           ,[AllowItemDisc]
           ,[AllowVouDisc]
           ,[UseMultiStoreInSales]
           ,[AllowedVoidInvCount]
           ,[DayOff]
           ,[VouDiscLimit]
           ,[MinTotalOfSalesVou]
		   ,[CheckCreditLimitInOrder]
		   ,[CompetitiveItemsInfoNextSerial]
		   ,[SupervisorNo]
		   ,[SupervisorName]
		   ,[SupervisorTel]
		   ,[CompanyBrancheID]
		   ,[UnLoadOrdersNextSerials]
		   ,[CreditLimit]
		   ,[SalesmanBalance]
		   ,[AllowAddDrawer]
		   ,[MaxDiscountPerc]
		   ,[SalesmanStockNextSerial]
		   ,[AllowReturnOrder]
		   ,[ReturnOrderNextSerial]
		   ,[VanTransferNextSerial]
		   ,AllowVanTransfer
		   ,AutoSendData
		   ,AllowSalesQuotation
		   ,SalesQuotationNextSerial
		   ,AllowItemsReplacment
		   ,ItemsReplacmentNextSerial
		   ,UserName
		   ,AllowAddProspectiveCust
		   ,SalesmanTel
		   ,AllowChangePriceInReturn
		   ,AllowItemDiscInReturn 
		   ,AllowVouDiscInReturn
		   ,AllowUnloadOrder,AllowMakeIssueItems,IssueItemsNextSerial,SalesInvoiceNextSerial_Credit,Ref3,MaxLoadOrderAmount,Ref2,DebitCreditNoteNextSerial,AllowDebitCreditNote
		   ,ReceiveItemsNextSerial,CashOnHand,PaymentsOrdersNextSerial,ref1)
			SELECT        SalesPersons.CompanyID, SalesPersons.ID, SalesPersons.Name, 
			(CASE WHEN @ClientActive = 19 THEN SalesPersons.Reference1 ELSE CASE WHEN @ClientActive = 30 THEN CAST(SalesPersons.ID AS Varchar(10)) ELSE SalesPersons.Name END END) AS Eng, 
									 SalesPersonsDevicePermissions.Password, 1 AS Active, SalesPersonTransactionsSerials.OrderTakingNextSerial, SalesPersonTransactionsSerials.SalesInvoiceNextSerial, 
									 SalesPersonTransactionsSerials.ReturnSalesNextSerial, SalesPersonTransactionsSerials.ReceiptNextSerial, SalesPersons.ID AS Store, SalesPersonsDevicePermissions.UseDefaultUnit, 
									 SalesPersonsDevicePermissions.ChangePrice, SalesPersonsDevicePermissions.MakeSalesInvoice, SalesPersonsDevicePermissions.MakeReturnSales, SalesPersonsDevicePermissions.MakeOrderTaking, 
									 SalesPersonsDevicePermissions.MakeReceipt, SalesPersonsDevicePermissions.MakeTransferOrder, SalesPersonTransactionsSerials.TransferOrderNextSerial, SalesPersons.GroupID AS SalesmanGroup_ID, 
									 SalesPersonsDevicePermissions.AllowCustStock, SalesPersonTransactionsSerials.CustStockNextSerial, SalesPersonsDevicePermissions.AllowChangeOrderStore, 
									 SalesPersonsDevicePermissions.AllowChangeOrderBusUnit, SalesPersonsDevicePermissions.AllowChangeOrderDocType, SalesPersonsDevicePermissions.AllowChangeOrderCustName, 
									 SalesPersonsDevicePermissions.AllowMakeBonus, SalesPersonsDevicePermissions.AllowAddCust, SalesPersonsDevicePermissions.AllowGetCustGPS, SalesPersonsDevicePermissions.AllowItemDisc, 
									 SalesPersonsDevicePermissions.AllowVouDisc, SalesPersonsDevicePermissions.UseMultiStoreInSales, SalesPersonsDevicePermissions.CanceledInvoiceNo, ISNULL(SalesPersons.DayOff, 0) AS Expr1, 
									 SalesPersonsDevicePermissions.VouDiscLimit, SalesPersonsDevicePermissions.MinTotalOfSalesVou, SalesPersonsDevicePermissions.CheckCreditLimitInOrder, 
									 SalesPersonTransactionsSerials.CompetitiveItemsInfoNextSerial, @SupervisorNo AS Expr2, @SupervisorName AS Expr3, case when @ClientActive = 105 then SalesPersons.SerialRef else  @SupervisorTel end AS Expr4, SalesPersons.CompanyBrancheID, 
									 SalesPersonTransactionsSerials.UnLoadOrdersNextSerials, SalesPersons.CreditLimit, 0 AS SalesmanBalance, SalesPersonsDevicePermissions.AllowAddDrawer, 
									 SalesPersonsDevicePermissions.MaxDiscountPerc, SalesPersonTransactionsSerials.SalesmanStockNextSerial, SalesPersonsDevicePermissions.AllowReturnOrder, 
									 SalesPersonTransactionsSerials.ReturnOrderNextSerial, ISNULL(SalesPersonTransactionsSerials.VanTransferNextSerial, 0) AS Expr5, ISNULL(SalesPersonsDevicePermissions.AllowVanTransfer, 0) AS Expr6, 
									 ISNULL(SalesPersons.AutoSendData, 0) AS Expr7, ISNULL(SalesPersonsDevicePermissions.AllowSalesQuotation, 0) AS AllowSalesQuotation, ISNULL(SalesPersonTransactionsSerials.SalesQuotationNextSerial, 
									 0) AS SalesQuotationNextSerial, ISNULL(SalesPersonsDevicePermissions.AllowItemsReplacement, 0) AS AllowItemsReplacment, ISNULL(SalesPersonTransactionsSerials.ItemsReplacementNextSerial, 0) 
									 AS ItemsReplacmentNextSerial, SalespersonsSecurity.UserID, SalesPersonsDevicePermissions.AllowAddProspectiveCustomer, SalesPersons.TelephoneNo,ISNULL(AllowChangePriceInReturn,0) AS AllowChangePriceInReturn, AllowItemDiscInReturn ,AllowVouDiscInReturn,AllowUnloadOrder ,AllowMakeIssueItems,IssueItemsNextSerial,ISNULL(SalesInvoiceNextSerial_Credit,0) AS SalesInvoiceNextSerial_Credit,case when SalesPersons.GroupID=5 then 3 else 4 end,ISNULL(MaxLoadOrderAmount,0) AS MaxLoadOrderAmount,SalesPersons.SalesPersonType,
									 DebitCreditNoteNextSerial,AllowDebitCreditNote,ReceiveItemsNextSerial,1000,PaymentsOrdersNextSerial, SalesPersons.groupid
			FROM            SalesPersons INNER JOIN
									 SalesPersonTransactionsSerials ON SalesPersons.CompanyID = SalesPersonTransactionsSerials.CompanyID AND SalesPersons.ID = SalesPersonTransactionsSerials.SalesPersonID INNER JOIN
									 SalesPersonsGroups ON SalesPersons.GroupID = SalesPersonsGroups.ID AND SalesPersons.CompanyID = SalesPersonsGroups.CompanyID INNER JOIN
									 SalesPersonsDevicePermissions ON SalesPersons.CompanyID = SalesPersonsDevicePermissions.CompanyID AND SalesPersons.PositionID = SalesPersonsDevicePermissions.PositionsID LEFT OUTER JOIN
									 SalespersonsSecurity ON SalesPersons.CompanyID = SalespersonsSecurity.CompanyID AND SalesPersons.ID = SalespersonsSecurity.SalespersonID
			WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo) AND (SalesPersonTransactionsSerials.SerYear = YEAR(@SendDate))

End
else if @ClientActive=136
Begin

INSERT INTO [OSFA_DB].[dbo].[OT_SalesmanMF] 
           ([CompNo]
           ,[SalesmanNo]
           ,[ArbSalesmanName]
           ,[EngSalesmanName]
           ,[Password]
           ,[Active]
           ,[NextSerial]
           ,[InvNextSerial]
           ,[RetInvNextSerial]
           ,[RecNextSerial]
           ,[StoreNo]
           ,[UseDefaultUnit]
           ,[AllowChangePrice]
           ,[AllowSales]
           ,[AllowReturnSales]
           ,[AllowOrder]
           ,[AllowRec]
           ,[AllowCons]
           ,[ConsNextSerial]
           ,[SalesmanGroup_ID]
           ,[AllowCustStock]
           ,[CustStockNextSerial]
           ,[AllowChangeOrderStore]
           ,[AllowChangeOrderBusUnit]
           ,[AllowChangeOrderDocType]
           ,[AllowChangeOrderCustName]
           ,[AllowMakeBonus]
           ,[AllowAddCust]
           ,[AllowGetCustGPS]
           ,[AllowItemDisc]
           ,[AllowVouDisc]
           ,[UseMultiStoreInSales]
           ,[AllowedVoidInvCount]
           ,[DayOff]
           ,[VouDiscLimit]
           ,[MinTotalOfSalesVou]
		   ,[CheckCreditLimitInOrder]
		   ,[CompetitiveItemsInfoNextSerial]
		   ,[SupervisorNo]
		   ,[SupervisorName]
		   ,[SupervisorTel]
		   ,[CompanyBrancheID]
		   ,[UnLoadOrdersNextSerials]
		   ,[CreditLimit]
		   ,[SalesmanBalance]
		   ,[AllowAddDrawer]
		   ,[MaxDiscountPerc]
		   ,[SalesmanStockNextSerial]
		   ,[AllowReturnOrder]
		   ,[ReturnOrderNextSerial]
		   ,[VanTransferNextSerial]
		   ,AllowVanTransfer
		   ,AutoSendData
		   ,AllowSalesQuotation
		   ,SalesQuotationNextSerial
		   ,AllowItemsReplacment
		   ,ItemsReplacmentNextSerial
		   ,UserName
		   ,AllowAddProspectiveCust
		   ,SalesmanTel
		   ,AllowChangePriceInReturn
		   ,AllowItemDiscInReturn 
		   ,AllowVouDiscInReturn
		   ,AllowUnloadOrder,AllowMakeIssueItems,IssueItemsNextSerial,SalesInvoiceNextSerial_Credit,Ref3,MaxLoadOrderAmount,Ref2,DebitCreditNoteNextSerial,AllowDebitCreditNote
		   ,ReceiveItemsNextSerial,CashOnHand,PaymentsOrdersNextSerial,Ref1)
			SELECT        SalesPersons.CompanyID, SalesPersons.ID, SalesPersons.Name, 
			(CASE WHEN @ClientActive = 19 THEN SalesPersons.Reference1 ELSE CASE WHEN @ClientActive = 30 THEN CAST(SalesPersons.ID AS Varchar(10)) ELSE SalesPersons.Name END END) AS Eng, 
									 SalesPersonsDevicePermissions.Password, 1 AS Active, SalesPersonTransactionsSerials.OrderTakingNextSerial, SalesPersonTransactionsSerials.SalesInvoiceNextSerial, 
									 SalesPersonTransactionsSerials.ReturnSalesNextSerial, SalesPersonTransactionsSerials.ReceiptNextSerial, SalesPersons.ID AS Store, SalesPersonsDevicePermissions.UseDefaultUnit, 
									 SalesPersonsDevicePermissions.ChangePrice, SalesPersonsDevicePermissions.MakeSalesInvoice, SalesPersonsDevicePermissions.MakeReturnSales, SalesPersonsDevicePermissions.MakeOrderTaking, 
									 SalesPersonsDevicePermissions.MakeReceipt, SalesPersonsDevicePermissions.MakeTransferOrder, SalesPersonTransactionsSerials.TransferOrderNextSerial, SalesPersons.GroupID AS SalesmanGroup_ID, 
									 SalesPersonsDevicePermissions.AllowCustStock, SalesPersonTransactionsSerials.CustStockNextSerial, SalesPersonsDevicePermissions.AllowChangeOrderStore, 
									 SalesPersonsDevicePermissions.AllowChangeOrderBusUnit, SalesPersonsDevicePermissions.AllowChangeOrderDocType, SalesPersonsDevicePermissions.AllowChangeOrderCustName, 
									 SalesPersonsDevicePermissions.AllowMakeBonus, SalesPersonsDevicePermissions.AllowAddCust, SalesPersonsDevicePermissions.AllowGetCustGPS, SalesPersonsDevicePermissions.AllowItemDisc, 
									 SalesPersonsDevicePermissions.AllowVouDisc, SalesPersonsDevicePermissions.UseMultiStoreInSales, SalesPersonsDevicePermissions.CanceledInvoiceNo, ISNULL(SalesPersons.DayOff, 0) AS Expr1, 
									 SalesPersonsDevicePermissions.VouDiscLimit, SalesPersonsDevicePermissions.MinTotalOfSalesVou, SalesPersonsDevicePermissions.CheckCreditLimitInOrder, 
									 SalesPersonTransactionsSerials.CompetitiveItemsInfoNextSerial, case when SalesPersons.Parent = -1 then '' else  @SupervisorNo end AS Expr2, case when SalesPersons.Parent = -1 then '' else  @SupervisorName end   AS Expr3, case when SalesPersons.Parent = -1 then '' else  @SupervisorTel end    , SalesPersons.CompanyBrancheID, 
									 SalesPersonTransactionsSerials.UnLoadOrdersNextSerials, SalesPersons.CreditLimit, 0 AS SalesmanBalance, SalesPersonsDevicePermissions.AllowAddDrawer, 
									 SalesPersonsDevicePermissions.MaxDiscountPerc, SalesPersonTransactionsSerials.SalesmanStockNextSerial, SalesPersonsDevicePermissions.AllowReturnOrder, 
									 SalesPersonTransactionsSerials.ReturnOrderNextSerial, ISNULL(SalesPersonTransactionsSerials.VanTransferNextSerial, 0) AS Expr5, ISNULL(SalesPersonsDevicePermissions.AllowVanTransfer, 0) AS Expr6, 
									 ISNULL(SalesPersons.AutoSendData, 0) AS Expr7, ISNULL(SalesPersonsDevicePermissions.AllowSalesQuotation, 0) AS AllowSalesQuotation, ISNULL(SalesPersonTransactionsSerials.SalesQuotationNextSerial, 
									 0) AS SalesQuotationNextSerial, ISNULL(SalesPersonsDevicePermissions.AllowItemsReplacement, 0) AS AllowItemsReplacment, ISNULL(SalesPersonTransactionsSerials.ItemsReplacementNextSerial, 0) 
									 AS ItemsReplacmentNextSerial, SalespersonsSecurity.UserID, SalesPersonsDevicePermissions.AllowAddProspectiveCustomer, SalesPersons.TelephoneNo,ISNULL(AllowChangePriceInReturn,0) AS AllowChangePriceInReturn, AllowItemDiscInReturn ,AllowVouDiscInReturn,AllowUnloadOrder ,AllowMakeIssueItems,IssueItemsNextSerial,ISNULL(SalesInvoiceNextSerial_Credit,0) AS SalesInvoiceNextSerial_Credit,case when @ClientActive=97 then SalesPersons.DebitAccount  when @ClientActive=105 then SalesPersons.[VehicleId] else SalesPersons.SerialRef End,ISNULL(MaxLoadOrderAmount,0) AS MaxLoadOrderAmount,SalesPersons.SalesPersonType,
									 DebitCreditNoteNextSerial,AllowDebitCreditNote,ReceiveItemsNextSerial,1000,PaymentsOrdersNextSerial,SalesPersons.ForeignName AS Ref1
			FROM            SalesPersons INNER JOIN
									 SalesPersonTransactionsSerials ON SalesPersons.CompanyID = SalesPersonTransactionsSerials.CompanyID AND SalesPersons.ID = SalesPersonTransactionsSerials.SalesPersonID INNER JOIN
									 SalesPersonsGroups ON SalesPersons.GroupID = SalesPersonsGroups.ID AND SalesPersons.CompanyID = SalesPersonsGroups.CompanyID INNER JOIN
									 SalesPersonsDevicePermissions ON SalesPersons.CompanyID = SalesPersonsDevicePermissions.CompanyID AND SalesPersons.PositionID = SalesPersonsDevicePermissions.PositionsID LEFT OUTER JOIN
									 SalespersonsSecurity ON SalesPersons.CompanyID = SalespersonsSecurity.CompanyID AND SalesPersons.ID = SalespersonsSecurity.SalespersonID
			WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo) AND (SalesPersonTransactionsSerials.SerYear = YEAR(@SendDate))

End


else if @ClientActive=154
Begin

INSERT INTO [OSFA_DB].[dbo].[OT_SalesmanMF] 
           ([CompNo]
           ,[SalesmanNo]
           ,[ArbSalesmanName]
           ,[EngSalesmanName]
           ,[Password]
           ,[Active]
           ,[NextSerial]
           ,[InvNextSerial]
           ,[RetInvNextSerial]
           ,[RecNextSerial]
           ,[StoreNo]
           ,[UseDefaultUnit]
           ,[AllowChangePrice]
           ,[AllowSales]
           ,[AllowReturnSales]
           ,[AllowOrder]
           ,[AllowRec]
           ,[AllowCons]
           ,[ConsNextSerial]
           ,[SalesmanGroup_ID]
           ,[AllowCustStock]
           ,[CustStockNextSerial]
           ,[AllowChangeOrderStore]
           ,[AllowChangeOrderBusUnit]
           ,[AllowChangeOrderDocType]
           ,[AllowChangeOrderCustName]
           ,[AllowMakeBonus]
           ,[AllowAddCust]
           ,[AllowGetCustGPS]
           ,[AllowItemDisc]
           ,[AllowVouDisc]
           ,[UseMultiStoreInSales]
           ,[AllowedVoidInvCount]
           ,[DayOff]
           ,[VouDiscLimit]
           ,[MinTotalOfSalesVou]
		   ,[CheckCreditLimitInOrder]
		   ,[CompetitiveItemsInfoNextSerial]
		   ,[SupervisorNo]
		   ,[SupervisorName]
		   ,[SupervisorTel]
		   ,[CompanyBrancheID]
		   ,[UnLoadOrdersNextSerials]
		   ,[CreditLimit]
		   ,[SalesmanBalance]
		   ,[AllowAddDrawer]
		   ,[MaxDiscountPerc]
		   ,[SalesmanStockNextSerial]
		   ,[AllowReturnOrder]
		   ,[ReturnOrderNextSerial]
		   ,[VanTransferNextSerial]
		   ,AllowVanTransfer
		   ,AutoSendData
		   ,AllowSalesQuotation
		   ,SalesQuotationNextSerial
		   ,AllowItemsReplacment
		   ,ItemsReplacmentNextSerial
		   ,UserName
		   ,AllowAddProspectiveCust
		   ,SalesmanTel
		   ,AllowChangePriceInReturn
		   ,AllowItemDiscInReturn 
		   ,AllowVouDiscInReturn
		   ,AllowUnloadOrder,AllowMakeIssueItems,IssueItemsNextSerial,SalesInvoiceNextSerial_Credit,Ref3,MaxLoadOrderAmount,Ref2,DebitCreditNoteNextSerial,AllowDebitCreditNote,ReceiveItemsNextSerial,CashOnHand,PaymentsOrdersNextSerial)
		SELECT        SalesPersons.CompanyID, SalesPersons.ID, SalesPersons.Name, (CASE WHEN @ClientActive = 19 THEN SalesPersons.Reference1 ELSE CASE WHEN @ClientActive = 30 THEN CAST(SalesPersons.ID AS Varchar(10)) 
                         ELSE SalesPersons.Name END END) AS Eng, SalesPersonsDevicePermissions.Password, 1 AS Active, SalesPersonTransactionsSerials.OrderTakingNextSerial, SalesPersonTransactionsSerials.SalesInvoiceNextSerial, 
                         SalesPersonTransactionsSerials.ReturnSalesNextSerial, SalesPersonTransactionsSerials.ReceiptNextSerial, SalesPersons.ID AS Store, SalesPersonsDevicePermissions.UseDefaultUnit, 
                         SalesPersonsDevicePermissions.ChangePrice, SalesPersonsDevicePermissions.MakeSalesInvoice, SalesPersonsDevicePermissions.MakeReturnSales, SalesPersonsDevicePermissions.MakeOrderTaking, 
                         SalesPersonsDevicePermissions.MakeReceipt, SalesPersonsDevicePermissions.MakeTransferOrder, SalesPersonTransactionsSerials.TransferOrderNextSerial, SalesPersons.GroupID AS SalesmanGroup_ID, 
                         SalesPersonsDevicePermissions.AllowCustStock, SalesPersonTransactionsSerials.CustStockNextSerial, SalesPersonsDevicePermissions.AllowChangeOrderStore, SalesPersonsDevicePermissions.AllowChangeOrderBusUnit, 
                         SalesPersonsDevicePermissions.AllowChangeOrderDocType, SalesPersonsDevicePermissions.AllowChangeOrderCustName, SalesPersonsDevicePermissions.AllowMakeBonus, 
                         SalesPersonsDevicePermissions.AllowAddCust, SalesPersonsDevicePermissions.AllowGetCustGPS, SalesPersonsDevicePermissions.AllowItemDisc, SalesPersonsDevicePermissions.AllowVouDisc, 
                         SalesPersonsDevicePermissions.UseMultiStoreInSales, SalesPersonsDevicePermissions.CanceledInvoiceNo, ISNULL(SalesPersons.DayOff, 0) AS Expr1, SalesPersonsDevicePermissions.VouDiscLimit, 
                         SalesPersonsDevicePermissions.MinTotalOfSalesVou, SalesPersonsDevicePermissions.CheckCreditLimitInOrder, SalesPersonTransactionsSerials.CompetitiveItemsInfoNextSerial, @SupervisorNo AS Expr2, 
                         @SupervisorName AS Expr3, @SupervisorTel AS Expr4, SalesPersons.CompanyBrancheID, SalesPersonTransactionsSerials.UnLoadOrdersNextSerials, SalesPersons.CreditLimit, 0 AS SalesmanBalance, 
                         SalesPersonsDevicePermissions.AllowAddDrawer, SalesPersonsDevicePermissions.MaxDiscountPerc, SalesPersonTransactionsSerials.SalesmanStockNextSerial, SalesPersonsDevicePermissions.AllowReturnOrder, 
                         SalesPersonTransactionsSerials.ReturnOrderNextSerial, ISNULL(SalesPersonTransactionsSerials.VanTransferNextSerial, 0) AS Expr5, ISNULL(SalesPersonsDevicePermissions.AllowVanTransfer, 0) AS Expr6, 
                         ISNULL(SalesPersons.AutoSendData, 0) AS Expr7, ISNULL(SalesPersonsDevicePermissions.AllowSalesQuotation, 0) AS AllowSalesQuotation, ISNULL(SalesPersonTransactionsSerials.SalesQuotationNextSerial, 0) 
                         AS SalesQuotationNextSerial, ISNULL(SalesPersonsDevicePermissions.AllowItemsReplacement, 0) AS AllowItemsReplacment, ISNULL(SalesPersonTransactionsSerials.ItemsReplacementNextSerial, 0) 
                         AS ItemsReplacmentNextSerial, SalespersonsSecurity.UserID, SalesPersonsDevicePermissions.AllowAddProspectiveCustomer, SalesPersons.TelephoneNo, 
                         ISNULL(SalesPersonsDevicePermissions.AllowChangePriceInReturn, 0) AS AllowChangePriceInReturn, SalesPersonsDevicePermissions.AllowItemDiscInReturn, SalesPersonsDevicePermissions.AllowVouDiscInReturn, 
                         SalesPersonsDevicePermissions.AllowUnloadOrder, SalesPersonsDevicePermissions.AllowMakeIssueItems, SalesPersonTransactionsSerials.IssueItemsNextSerial, 
                         ISNULL(SalesPersonTransactionsSerials.SalesInvoiceNextSerial_Credit, 0) AS SalesInvoiceNextSerial_Credit, 
                         DeliveryCars.name As Ref3, ISNULL(SalesPersons.MaxLoadOrderAmount, 0) 
                         AS MaxLoadOrderAmount, SalesPersons.SalesPersonType, SalesPersonTransactionsSerials.DebitCreditNoteNextSerial, SalesPersonsDevicePermissions.AllowDebitCreditNote, 
                         SalesPersonTransactionsSerials.ReceiveItemsNextSerial, 1000 AS Expr9, SalesPersonTransactionsSerials.PaymentsOrdersNextSerial
FROM            SalesPersons INNER JOIN
                         SalesPersonTransactionsSerials ON SalesPersons.CompanyID = SalesPersonTransactionsSerials.CompanyID AND SalesPersons.ID = SalesPersonTransactionsSerials.SalesPersonID INNER JOIN
                         SalesPersonsGroups ON SalesPersons.GroupID = SalesPersonsGroups.ID AND SalesPersons.CompanyID = SalesPersonsGroups.CompanyID INNER JOIN
                         SalesPersonsDevicePermissions ON SalesPersons.CompanyID = SalesPersonsDevicePermissions.CompanyID AND SalesPersons.PositionID = SalesPersonsDevicePermissions.PositionsID INNER JOIN
                         DeliveryCars ON SalesPersons.CompanyID = DeliveryCars.CompanyID AND SalesPersons.CarID = DeliveryCars.ID LEFT OUTER JOIN
                         SalespersonsSecurity ON SalesPersons.CompanyID = SalespersonsSecurity.CompanyID AND SalesPersons.ID = SalespersonsSecurity.SalespersonID
WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo) AND (SalesPersonTransactionsSerials.SerYear = YEAR(@SendDate))
End
else if @ClientActive=32 and (@SalesmanNo in (11,10,12))
begin

INSERT INTO [OSFA_DB].[dbo].[OT_SalesmanMF] 
           ([CompNo]
           ,[SalesmanNo]
           ,[ArbSalesmanName]
           ,[EngSalesmanName]
           ,[Password]
           ,[Active]
           ,[NextSerial]
           ,[InvNextSerial]
           ,[RetInvNextSerial]
           ,[RecNextSerial]
           ,[StoreNo]
           ,[UseDefaultUnit]
           ,[AllowChangePrice]
           ,[AllowSales]
           ,[AllowReturnSales]
           ,[AllowOrder]
           ,[AllowRec]
           ,[AllowCons]
           ,[ConsNextSerial]
           ,[SalesmanGroup_ID]
           ,[AllowCustStock]
           ,[CustStockNextSerial]
           ,[AllowChangeOrderStore]
           ,[AllowChangeOrderBusUnit]
           ,[AllowChangeOrderDocType]
           ,[AllowChangeOrderCustName]
           ,[AllowMakeBonus]
           ,[AllowAddCust]
           ,[AllowGetCustGPS]
           ,[AllowItemDisc]
           ,[AllowVouDisc]
           ,[UseMultiStoreInSales]
           ,[AllowedVoidInvCount]
           ,[DayOff]
           ,[VouDiscLimit]
           ,[MinTotalOfSalesVou]
		   ,[CheckCreditLimitInOrder]
		   ,[CompetitiveItemsInfoNextSerial]
		   ,[SupervisorNo]
		   ,[SupervisorName]
		   ,[SupervisorTel]
		   ,[CompanyBrancheID]
		   ,[UnLoadOrdersNextSerials]
		   ,[CreditLimit]
		   ,[SalesmanBalance]
		   ,[AllowAddDrawer]
		   ,[MaxDiscountPerc]
		   ,[SalesmanStockNextSerial]
		   ,[AllowReturnOrder]
		   ,[ReturnOrderNextSerial]
		   ,[VanTransferNextSerial]
		   ,AllowVanTransfer
		   ,AutoSendData
		   ,AllowSalesQuotation
		   ,SalesQuotationNextSerial
		   ,AllowItemsReplacment
		   ,ItemsReplacmentNextSerial
		   ,UserName
		   ,AllowAddProspectiveCust
		   ,SalesmanTel
		   ,AllowChangePriceInReturn
		   ,AllowItemDiscInReturn 
		   ,AllowVouDiscInReturn
		   ,AllowUnloadOrder
		   ,Ref3,ReceiveItemsNextSerial,CashOnHand,PaymentsOrdersNextSerial)
			SELECT        SalesPersons.CompanyID, SalesPersons.ID, SalesPersons.Name, 
			(CASE WHEN @ClientActive = 19 THEN SalesPersons.Reference1 ELSE CASE WHEN @ClientActive = 30 THEN CAST(SalesPersons.ID AS Varchar(10)) ELSE SalesPersons.Name END END) AS Eng, 
									 SalesPersonsDevicePermissions.Password, 1 AS Active, SalesPersonTransactionsSerials.OrderTakingNextSerial, SalesPersonTransactionsSerials.SalesInvoiceNextSerial, 
									 SalesPersonTransactionsSerials.ReturnSalesNextSerial, SalesPersonTransactionsSerials.ReceiptNextSerial, SalesPersons.ID AS Store, SalesPersonsDevicePermissions.UseDefaultUnit, 
									 SalesPersonsDevicePermissions.ChangePrice, SalesPersonsDevicePermissions.MakeSalesInvoice, SalesPersonsDevicePermissions.MakeReturnSales, SalesPersonsDevicePermissions.MakeOrderTaking, 
									 SalesPersonsDevicePermissions.MakeReceipt, SalesPersonsDevicePermissions.MakeTransferOrder, SalesPersonTransactionsSerials.TransferOrderNextSerial, SalesPersons.GroupID AS SalesmanGroup_ID, 
									 SalesPersonsDevicePermissions.AllowCustStock, SalesPersonTransactionsSerials.CustStockNextSerial, SalesPersonsDevicePermissions.AllowChangeOrderStore, 
									 SalesPersonsDevicePermissions.AllowChangeOrderBusUnit, SalesPersonsDevicePermissions.AllowChangeOrderDocType, SalesPersonsDevicePermissions.AllowChangeOrderCustName, 
									 SalesPersonsDevicePermissions.AllowMakeBonus, SalesPersonsDevicePermissions.AllowAddCust, SalesPersonsDevicePermissions.AllowGetCustGPS, SalesPersonsDevicePermissions.AllowItemDisc, 
									 SalesPersonsDevicePermissions.AllowVouDisc, SalesPersonsDevicePermissions.UseMultiStoreInSales, SalesPersonsDevicePermissions.CanceledInvoiceNo, ISNULL(SalesPersons.DayOff, 0) AS Expr1, 
									 SalesPersonsDevicePermissions.VouDiscLimit, SalesPersonsDevicePermissions.MinTotalOfSalesVou, SalesPersonsDevicePermissions.CheckCreditLimitInOrder, 
									 SalesPersonTransactionsSerials.CompetitiveItemsInfoNextSerial, @SupervisorNo AS Expr2, @SupervisorName AS Expr3, @SupervisorTel AS Expr4, SalesPersons.CompanyBrancheID, 
									 SalesPersonTransactionsSerials.UnLoadOrdersNextSerials, SalesPersons.CreditLimit, 0 AS SalesmanBalance, SalesPersonsDevicePermissions.AllowAddDrawer, 
									 SalesPersonsDevicePermissions.MaxDiscountPerc, SalesPersonTransactionsSerials.SalesmanStockNextSerial, SalesPersonsDevicePermissions.AllowReturnOrder, 
									 SalesPersonTransactionsSerials.ReturnOrderNextSerial, ISNULL(SalesPersonTransactionsSerials.VanTransferNextSerial, 0) AS Expr5, ISNULL(SalesPersonsDevicePermissions.AllowVanTransfer, 0) AS Expr6, 
									 ISNULL(SalesPersons.AutoSendData, 0) AS Expr7, ISNULL(SalesPersonsDevicePermissions.AllowSalesQuotation, 0) AS AllowSalesQuotation, ISNULL(SalesPersonTransactionsSerials.SalesQuotationNextSerial, 
									 0) AS SalesQuotationNextSerial, ISNULL(SalesPersonsDevicePermissions.AllowItemsReplacement, 0) AS AllowItemsReplacment, ISNULL(SalesPersonTransactionsSerials.ItemsReplacementNextSerial, 0) 
									 AS ItemsReplacmentNextSerial, SalespersonsSecurity.UserID, SalesPersonsDevicePermissions.AllowAddProspectiveCustomer, SalesPersons.TelephoneNo,ISNULL(AllowChangePriceInReturn,0) AS AllowChangePriceInReturn, AllowItemDiscInReturn ,AllowVouDiscInReturn,AllowUnloadOrder,SerialRef
									 ,ReceiveItemsNextSerial,1000,PaymentsOrdersNextSerial
			FROM            SalesPersons INNER JOIN
									 SalesPersonTransactionsSerials ON SalesPersons.CompanyID = SalesPersonTransactionsSerials.CompanyID AND SalesPersons.ID = SalesPersonTransactionsSerials.SalesPersonID INNER JOIN
									 SalesPersonsGroups ON SalesPersons.GroupID = SalesPersonsGroups.ID AND SalesPersons.CompanyID = SalesPersonsGroups.CompanyID INNER JOIN
									 SalesPersonsDevicePermissions ON SalesPersons.CompanyID = SalesPersonsDevicePermissions.CompanyID AND SalesPersons.PositionID = SalesPersonsDevicePermissions.PositionsID LEFT OUTER JOIN
									 SalespersonsSecurity ON SalesPersons.CompanyID = SalespersonsSecurity.CompanyID AND SalesPersons.ID = SalespersonsSecurity.SalespersonID
			WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo) AND (SalesPersonTransactionsSerials.SerYear = YEAR(@SendDate))
end

Else If @ClientActive=165
Begin
INSERT INTO [OSFA_DB].[dbo].[OT_SalesmanMF] 
           ([CompNo]
           ,[SalesmanNo]
           ,[ArbSalesmanName]
           ,[EngSalesmanName]
           ,[Password]
           ,[Active]
           ,[NextSerial]
           ,[InvNextSerial]
           ,[RetInvNextSerial]
           ,[RecNextSerial]
           ,[StoreNo]
           ,[UseDefaultUnit]
           ,[AllowChangePrice]
           ,[AllowSales]
           ,[AllowReturnSales]
           ,[AllowOrder]
           ,[AllowRec]
           ,[AllowCons]
           ,[ConsNextSerial]
           ,[SalesmanGroup_ID]
           ,[AllowCustStock]
           ,[CustStockNextSerial]
           ,[AllowChangeOrderStore]
           ,[AllowChangeOrderBusUnit]
           ,[AllowChangeOrderDocType]
           ,[AllowChangeOrderCustName]
           ,[AllowMakeBonus]
           ,[AllowAddCust]
           ,[AllowGetCustGPS]
           ,[AllowItemDisc]
           ,[AllowVouDisc]
           ,[UseMultiStoreInSales]
           ,[AllowedVoidInvCount]
           ,[DayOff]
           ,[VouDiscLimit]
           ,[MinTotalOfSalesVou]
		   ,[CheckCreditLimitInOrder]
		   ,[CompetitiveItemsInfoNextSerial]
		   ,[SupervisorNo]
		   ,[SupervisorName]
		   ,[SupervisorTel]
		   ,[CompanyBrancheID]
		   ,[UnLoadOrdersNextSerials]
		   ,[CreditLimit]
		   ,[SalesmanBalance]
		   ,[AllowAddDrawer]
		   ,[MaxDiscountPerc]
		   ,[SalesmanStockNextSerial]
		   ,[AllowReturnOrder]
		   ,[ReturnOrderNextSerial]
		   ,[VanTransferNextSerial]
		   ,AllowVanTransfer
		   ,AutoSendData
		   ,AllowSalesQuotation
		   ,SalesQuotationNextSerial
		   ,AllowItemsReplacment
		   ,ItemsReplacmentNextSerial
		   ,UserName
		   ,AllowAddProspectiveCust
		   ,SalesmanTel
		   ,AllowChangePriceInReturn
		   ,AllowItemDiscInReturn 
		   ,AllowVouDiscInReturn
		   ,AllowUnloadOrder,AllowMakeIssueItems,IssueItemsNextSerial,SalesInvoiceNextSerial_Credit,Ref3,MaxLoadOrderAmount,Ref2,DebitCreditNoteNextSerial,AllowDebitCreditNote,ReceiveItemsNextSerial,CashOnHand,PaymentsOrdersNextSerial
		   , Ref1)
			SELECT        SalesPersons.CompanyID, SalesPersons.ID, SalesPersons.Name, 
			(CASE WHEN @ClientActive = 19 THEN SalesPersons.Reference1 ELSE CASE WHEN @ClientActive = 30 THEN CAST(SalesPersons.ID AS Varchar(10)) ELSE SalesPersons.Name END END) AS Eng, 
									 SalesPersonsDevicePermissions.Password, 1 AS Active, SalesPersonTransactionsSerials.OrderTakingNextSerial, SalesPersonTransactionsSerials.SalesInvoiceNextSerial, 
									 SalesPersonTransactionsSerials.ReturnSalesNextSerial, SalesPersonTransactionsSerials.ReceiptNextSerial, SalesPersons.ID AS Store, SalesPersonsDevicePermissions.UseDefaultUnit, 
									 SalesPersonsDevicePermissions.ChangePrice, SalesPersonsDevicePermissions.MakeSalesInvoice, SalesPersonsDevicePermissions.MakeReturnSales, SalesPersonsDevicePermissions.MakeOrderTaking, 
									 SalesPersonsDevicePermissions.MakeReceipt, SalesPersonsDevicePermissions.MakeTransferOrder, SalesPersonTransactionsSerials.TransferOrderNextSerial, SalesPersons.GroupID AS SalesmanGroup_ID, 
									 SalesPersonsDevicePermissions.AllowCustStock, SalesPersonTransactionsSerials.CustStockNextSerial, SalesPersonsDevicePermissions.AllowChangeOrderStore, 
									 SalesPersonsDevicePermissions.AllowChangeOrderBusUnit, SalesPersonsDevicePermissions.AllowChangeOrderDocType, SalesPersonsDevicePermissions.AllowChangeOrderCustName, 
									 SalesPersonsDevicePermissions.AllowMakeBonus, SalesPersonsDevicePermissions.AllowAddCust, SalesPersonsDevicePermissions.AllowGetCustGPS, SalesPersonsDevicePermissions.AllowItemDisc, 
									 SalesPersonsDevicePermissions.AllowVouDisc, SalesPersonsDevicePermissions.UseMultiStoreInSales, SalesPersonsDevicePermissions.CanceledInvoiceNo, ISNULL(SalesPersons.DayOff, 0) AS Expr1, 
									 SalesPersonsDevicePermissions.VouDiscLimit, SalesPersonsDevicePermissions.MinTotalOfSalesVou, SalesPersonsDevicePermissions.CheckCreditLimitInOrder, 
									 SalesPersonTransactionsSerials.CompetitiveItemsInfoNextSerial, @SupervisorNo AS Expr2, @SupervisorName AS Expr3, @SupervisorTel , SalesPersons.CompanyBrancheID, 
									 SalesPersonTransactionsSerials.UnLoadOrdersNextSerials, SalesPersons.CreditLimit, 0 AS SalesmanBalance, SalesPersonsDevicePermissions.AllowAddDrawer, 
									 SalesPersonsDevicePermissions.MaxDiscountPerc, SalesPersonTransactionsSerials.SalesmanStockNextSerial, SalesPersonsDevicePermissions.AllowReturnOrder, 
									 SalesPersonTransactionsSerials.ReturnOrderNextSerial, ISNULL(SalesPersonTransactionsSerials.VanTransferNextSerial, 0) AS Expr5, ISNULL(SalesPersonsDevicePermissions.AllowVanTransfer, 0) AS Expr6, 
									 ISNULL(SalesPersons.AutoSendData, 0) AS Expr7, ISNULL(SalesPersonsDevicePermissions.AllowSalesQuotation, 0) AS AllowSalesQuotation, ISNULL(SalesPersonTransactionsSerials.SalesQuotationNextSerial, 
									 0) AS SalesQuotationNextSerial, ISNULL(SalesPersonsDevicePermissions.AllowItemsReplacement, 0) AS AllowItemsReplacment, ISNULL(SalesPersonTransactionsSerials.ItemsReplacementNextSerial, 0) 
									 AS ItemsReplacmentNextSerial, SalespersonsSecurity.UserID, SalesPersonsDevicePermissions.AllowAddProspectiveCustomer, SalesPersons.TelephoneNo,ISNULL(AllowChangePriceInReturn,0) AS AllowChangePriceInReturn, AllowItemDiscInReturn ,AllowVouDiscInReturn,AllowUnloadOrder ,AllowMakeIssueItems,IssueItemsNextSerial,ISNULL(SalesInvoiceNextSerial_Credit,0) AS SalesInvoiceNextSerial_Credit,case when @ClientActive=97 then SalesPersons.DebitAccount  when @ClientActive=105 then SalesPersons.[VehicleId] else SalesPersons.SerialRef End,ISNULL(MaxLoadOrderAmount,0) AS MaxLoadOrderAmount,SalesPersons.SalesPersonType,
									 DebitCreditNoteNextSerial,AllowDebitCreditNote,ReceiveItemsNextSerial,1000,PaymentsOrdersNextSerial, salespersons.Reference1 as Ref1
			FROM            SalesPersons INNER JOIN
									 SalesPersonTransactionsSerials ON SalesPersons.CompanyID = SalesPersonTransactionsSerials.CompanyID AND SalesPersons.ID = SalesPersonTransactionsSerials.SalesPersonID INNER JOIN
									 SalesPersonsGroups ON SalesPersons.GroupID = SalesPersonsGroups.ID AND SalesPersons.CompanyID = SalesPersonsGroups.CompanyID INNER JOIN
									 SalesPersonsDevicePermissions ON SalesPersons.CompanyID = SalesPersonsDevicePermissions.CompanyID AND SalesPersons.PositionID = SalesPersonsDevicePermissions.PositionsID LEFT OUTER JOIN
									 SalespersonsSecurity ON SalesPersons.CompanyID = SalespersonsSecurity.CompanyID AND SalesPersons.ID = SalespersonsSecurity.SalespersonID
			WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo) AND (SalesPersonTransactionsSerials.SerYear = YEAR(@SendDate))



End
else if @ClientActive=15 and @CompNo in(1,11)
begin

Declare @SalesmanTypeID int =(select SalesPersonType from salespersons where companyid=@compno and id =@salesmanno)
select @SalesmanTypeID SalesmanTypeID
INSERT INTO [OSFA_DB].[dbo].[OT_SalesmanMF] 
           ([CompNo]
           ,[SalesmanNo]
           ,[ArbSalesmanName]
           ,[EngSalesmanName]
           ,[Password]
           ,[Active]
           ,[NextSerial]
           ,[InvNextSerial]
           ,[RetInvNextSerial]
           ,[RecNextSerial]
           ,[StoreNo]
           ,[UseDefaultUnit]
           ,[AllowChangePrice]
           ,[AllowSales]
           ,[AllowReturnSales]
           ,[AllowOrder]
           ,[AllowRec]
           ,[AllowCons]
           ,[ConsNextSerial]
           ,[SalesmanGroup_ID]
           ,[AllowCustStock]
           ,[CustStockNextSerial]
           ,[AllowChangeOrderStore]
           ,[AllowChangeOrderBusUnit]
           ,[AllowChangeOrderDocType]
           ,[AllowChangeOrderCustName]
           ,[AllowMakeBonus]
           ,[AllowAddCust]
           ,[AllowGetCustGPS]
           ,[AllowItemDisc]
           ,[AllowVouDisc]
           ,[UseMultiStoreInSales]
           ,[AllowedVoidInvCount]
           ,[DayOff]
           ,[VouDiscLimit]
           ,[MinTotalOfSalesVou]
		   ,[CheckCreditLimitInOrder]
		   ,[CompetitiveItemsInfoNextSerial]
		   ,[SupervisorNo]
		   ,[SupervisorName]
		   ,[SupervisorTel]
		   ,[CompanyBrancheID]
		   ,[UnLoadOrdersNextSerials]
		   ,[CreditLimit]
		   ,[SalesmanBalance]
		   ,[AllowAddDrawer]
		   ,[MaxDiscountPerc]
		   ,[SalesmanStockNextSerial]
		   ,[AllowReturnOrder]
		   ,[ReturnOrderNextSerial]
		   ,[VanTransferNextSerial]
		   ,AllowVanTransfer
		   ,AutoSendData
		   ,AllowSalesQuotation
		   ,SalesQuotationNextSerial
		   ,AllowItemsReplacment
		   ,ItemsReplacmentNextSerial
		   ,UserName
		   ,AllowAddProspectiveCust
		   ,SalesmanTel
		   ,AllowChangePriceInReturn
		   ,AllowItemDiscInReturn 
		   ,AllowVouDiscInReturn
		   ,AllowUnloadOrder,AllowMakeIssueItems,IssueItemsNextSerial,SalesInvoiceNextSerial_Credit,Ref3,MaxLoadOrderAmount,Ref2,DebitCreditNoteNextSerial,AllowDebitCreditNote,ReceiveItemsNextSerial,CashOnHand,PaymentsOrdersNextSerial
		   ,ref1)
			SELECT        SalesPersons.CompanyID, SalesPersons.ID, SalesPersons.Name, 
			(CASE WHEN @ClientActive = 19 THEN SalesPersons.Reference1 ELSE CASE WHEN @ClientActive = 30 THEN CAST(SalesPersons.ID AS Varchar(10)) ELSE SalesPersons.Name END END) AS Eng, 
									 SalesPersonsDevicePermissions.Password, 1 AS Active, SalesPersonTransactionsSerials.OrderTakingNextSerial, SalesPersonTransactionsSerials.SalesInvoiceNextSerial, 
									 SalesPersonTransactionsSerials.ReturnSalesNextSerial, SalesPersonTransactionsSerials.ReceiptNextSerial, SalesPersons.ID AS Store, SalesPersonsDevicePermissions.UseDefaultUnit, 
									 SalesPersonsDevicePermissions.ChangePrice, SalesPersonsDevicePermissions.MakeSalesInvoice, SalesPersonsDevicePermissions.MakeReturnSales, SalesPersonsDevicePermissions.MakeOrderTaking, 
									 SalesPersonsDevicePermissions.MakeReceipt, SalesPersonsDevicePermissions.MakeTransferOrder, SalesPersonTransactionsSerials.TransferOrderNextSerial, SalesPersons.GroupID AS SalesmanGroup_ID, 
									 SalesPersonsDevicePermissions.AllowCustStock, SalesPersonTransactionsSerials.CustStockNextSerial, SalesPersonsDevicePermissions.AllowChangeOrderStore, 
									 SalesPersonsDevicePermissions.AllowChangeOrderBusUnit, SalesPersonsDevicePermissions.AllowChangeOrderDocType, SalesPersonsDevicePermissions.AllowChangeOrderCustName, 
									 SalesPersonsDevicePermissions.AllowMakeBonus, SalesPersonsDevicePermissions.AllowAddCust, SalesPersonsDevicePermissions.AllowGetCustGPS, SalesPersonsDevicePermissions.AllowItemDisc, 
									 SalesPersonsDevicePermissions.AllowVouDisc, SalesPersonsDevicePermissions.UseMultiStoreInSales, SalesPersonsDevicePermissions.CanceledInvoiceNo, ISNULL(SalesPersons.DayOff, 0) AS Expr1, 
									 SalesPersonsDevicePermissions.VouDiscLimit, SalesPersonsDevicePermissions.MinTotalOfSalesVou, SalesPersonsDevicePermissions.CheckCreditLimitInOrder, 
									 SalesPersonTransactionsSerials.CompetitiveItemsInfoNextSerial, @SupervisorNo AS Expr2, @SupervisorName AS Expr3, @SupervisorTel , SalesPersons.CompanyBrancheID, 
									 SalesPersonTransactionsSerials.UnLoadOrdersNextSerials, SalesPersons.CreditLimit, 0 AS SalesmanBalance, SalesPersonsDevicePermissions.AllowAddDrawer, 
									 SalesPersonsDevicePermissions.MaxDiscountPerc, SalesPersonTransactionsSerials.SalesmanStockNextSerial, SalesPersonsDevicePermissions.AllowReturnOrder, 
									 SalesPersonTransactionsSerials.ReturnOrderNextSerial, ISNULL(SalesPersonTransactionsSerials.VanTransferNextSerial, 0) AS Expr5, ISNULL(SalesPersonsDevicePermissions.AllowVanTransfer, 0) AS Expr6, 
									 ISNULL(SalesPersons.AutoSendData, 0) AS Expr7, ISNULL(SalesPersonsDevicePermissions.AllowSalesQuotation, 0) AS AllowSalesQuotation, ISNULL(SalesPersonTransactionsSerials.SalesQuotationNextSerial, 
									 0) AS SalesQuotationNextSerial, ISNULL(SalesPersonsDevicePermissions.AllowItemsReplacement, 0) AS AllowItemsReplacment, ISNULL(SalesPersonTransactionsSerials.ItemsReplacementNextSerial, 0) 
									 AS ItemsReplacmentNextSerial, SalespersonsSecurity.UserID, SalesPersonsDevicePermissions.AllowAddProspectiveCustomer, SalesPersons.TelephoneNo,ISNULL(AllowChangePriceInReturn,0) AS AllowChangePriceInReturn, AllowItemDiscInReturn ,AllowVouDiscInReturn,AllowUnloadOrder ,AllowMakeIssueItems,IssueItemsNextSerial,ISNULL(SalesInvoiceNextSerial_Credit,0) AS SalesInvoiceNextSerial_Credit,case when @ClientActive=97 then SalesPersons.DebitAccount  when @ClientActive=105 then SalesPersons.[VehicleId] else SalesPersons.SerialRef End,ISNULL(MaxLoadOrderAmount,0) AS MaxLoadOrderAmount,SalesPersons.SalesPersonType,
									 DebitCreditNoteNextSerial,AllowDebitCreditNote,ReceiveItemsNextSerial,1000,PaymentsOrdersNextSerial,@SalesmanTypeID
			FROM            SalesPersons INNER JOIN
									 SalesPersonTransactionsSerials ON SalesPersons.CompanyID = SalesPersonTransactionsSerials.CompanyID AND SalesPersons.ID = SalesPersonTransactionsSerials.SalesPersonID INNER JOIN
									 SalesPersonsGroups ON SalesPersons.GroupID = SalesPersonsGroups.ID AND SalesPersons.CompanyID = SalesPersonsGroups.CompanyID INNER JOIN
									 SalesPersonsDevicePermissions ON SalesPersons.CompanyID = SalesPersonsDevicePermissions.CompanyID AND SalesPersons.PositionID = SalesPersonsDevicePermissions.PositionsID LEFT OUTER JOIN
									 SalespersonsSecurity ON SalesPersons.CompanyID = SalespersonsSecurity.CompanyID AND SalesPersons.ID = SalespersonsSecurity.SalespersonID
			WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo) AND (SalesPersonTransactionsSerials.SerYear = YEAR(@SendDate))

End
else 
Begin
Select 'O.ABUARAB3'
INSERT INTO [OSFA_DB].[dbo].[OT_SalesmanMF] 
           ([CompNo]
           ,[SalesmanNo]
           ,[ArbSalesmanName]
           ,[EngSalesmanName]
           ,[Password]
           ,[Active]
           ,[NextSerial]
           ,[InvNextSerial]
           ,[RetInvNextSerial]
           ,[RecNextSerial]
           ,[StoreNo]
           ,[UseDefaultUnit]
           ,[AllowChangePrice]
           ,[AllowSales]
           ,[AllowReturnSales]
           ,[AllowOrder]
           ,[AllowRec]
           ,[AllowCons]
           ,[ConsNextSerial]
           ,[SalesmanGroup_ID]
           ,[AllowCustStock]
           ,[CustStockNextSerial]
           ,[AllowChangeOrderStore]
           ,[AllowChangeOrderBusUnit]
           ,[AllowChangeOrderDocType]
           ,[AllowChangeOrderCustName]
           ,[AllowMakeBonus]
           ,[AllowAddCust]
           ,[AllowGetCustGPS]
           ,[AllowItemDisc]
           ,[AllowVouDisc]
           ,[UseMultiStoreInSales]
           ,[AllowedVoidInvCount]
           ,[DayOff]
           ,[VouDiscLimit]
           ,[MinTotalOfSalesVou]
		   ,[CheckCreditLimitInOrder]
		   ,[CompetitiveItemsInfoNextSerial]
		   ,[SupervisorNo]
		   ,[SupervisorName]
		   ,[SupervisorTel]
		   ,[CompanyBrancheID]
		   ,[UnLoadOrdersNextSerials]
		   ,[CreditLimit]
		   ,[SalesmanBalance]
		   ,[AllowAddDrawer]
		   ,[MaxDiscountPerc]
		   ,[SalesmanStockNextSerial]
		   ,[AllowReturnOrder]
		   ,[ReturnOrderNextSerial]
		   ,[VanTransferNextSerial]
		   ,AllowVanTransfer
		   ,AutoSendData
		   ,AllowSalesQuotation
		   ,SalesQuotationNextSerial
		   ,AllowItemsReplacment
		   ,ItemsReplacmentNextSerial
		   ,UserName
		   ,AllowAddProspectiveCust
		   ,SalesmanTel
		   ,AllowChangePriceInReturn
		   ,AllowItemDiscInReturn 
		   ,AllowVouDiscInReturn
		   ,AllowUnloadOrder,AllowMakeIssueItems,IssueItemsNextSerial,SalesInvoiceNextSerial_Credit,Ref3,MaxLoadOrderAmount,Ref2,DebitCreditNoteNextSerial,AllowDebitCreditNote,ReceiveItemsNextSerial,CashOnHand,PaymentsOrdersNextSerial)
			SELECT        SalesPersons.CompanyID, SalesPersons.ID, SalesPersons.Name, 
			(CASE WHEN @ClientActive = 19 THEN SalesPersons.Reference1 ELSE CASE WHEN @ClientActive = 30 THEN CAST(SalesPersons.ID AS Varchar(10)) ELSE SalesPersons.Name END END) AS Eng, 
									 SalesPersonsDevicePermissions.Password, 1 AS Active, SalesPersonTransactionsSerials.OrderTakingNextSerial, SalesPersonTransactionsSerials.SalesInvoiceNextSerial, 
									 SalesPersonTransactionsSerials.ReturnSalesNextSerial, SalesPersonTransactionsSerials.ReceiptNextSerial, SalesPersons.ID AS Store, SalesPersonsDevicePermissions.UseDefaultUnit, 
									 SalesPersonsDevicePermissions.ChangePrice, SalesPersonsDevicePermissions.MakeSalesInvoice, SalesPersonsDevicePermissions.MakeReturnSales, SalesPersonsDevicePermissions.MakeOrderTaking, 
									 SalesPersonsDevicePermissions.MakeReceipt, SalesPersonsDevicePermissions.MakeTransferOrder, SalesPersonTransactionsSerials.TransferOrderNextSerial, SalesPersons.GroupID AS SalesmanGroup_ID, 
									 SalesPersonsDevicePermissions.AllowCustStock, SalesPersonTransactionsSerials.CustStockNextSerial, SalesPersonsDevicePermissions.AllowChangeOrderStore, 
									 SalesPersonsDevicePermissions.AllowChangeOrderBusUnit, SalesPersonsDevicePermissions.AllowChangeOrderDocType, SalesPersonsDevicePermissions.AllowChangeOrderCustName, 
									 SalesPersonsDevicePermissions.AllowMakeBonus, SalesPersonsDevicePermissions.AllowAddCust, SalesPersonsDevicePermissions.AllowGetCustGPS, SalesPersonsDevicePermissions.AllowItemDisc, 
									 SalesPersonsDevicePermissions.AllowVouDisc, SalesPersonsDevicePermissions.UseMultiStoreInSales, SalesPersonsDevicePermissions.CanceledInvoiceNo, ISNULL(SalesPersons.DayOff, 0) AS Expr1, 
									 SalesPersonsDevicePermissions.VouDiscLimit, SalesPersonsDevicePermissions.MinTotalOfSalesVou, SalesPersonsDevicePermissions.CheckCreditLimitInOrder, 
									 SalesPersonTransactionsSerials.CompetitiveItemsInfoNextSerial, @SupervisorNo AS Expr2, @SupervisorName AS Expr3, @SupervisorTel , SalesPersons.CompanyBrancheID, 
									 SalesPersonTransactionsSerials.UnLoadOrdersNextSerials, SalesPersons.CreditLimit, 0 AS SalesmanBalance, SalesPersonsDevicePermissions.AllowAddDrawer, 
									 SalesPersonsDevicePermissions.MaxDiscountPerc, SalesPersonTransactionsSerials.SalesmanStockNextSerial, SalesPersonsDevicePermissions.AllowReturnOrder, 
									 SalesPersonTransactionsSerials.ReturnOrderNextSerial, ISNULL(SalesPersonTransactionsSerials.VanTransferNextSerial, 0) AS Expr5, ISNULL(SalesPersonsDevicePermissions.AllowVanTransfer, 0) AS Expr6, 
									 ISNULL(SalesPersons.AutoSendData, 0) AS Expr7, ISNULL(SalesPersonsDevicePermissions.AllowSalesQuotation, 0) AS AllowSalesQuotation, ISNULL(SalesPersonTransactionsSerials.SalesQuotationNextSerial, 
									 0) AS SalesQuotationNextSerial, ISNULL(SalesPersonsDevicePermissions.AllowItemsReplacement, 0) AS AllowItemsReplacment, ISNULL(SalesPersonTransactionsSerials.ItemsReplacementNextSerial, 0) 
									 AS ItemsReplacmentNextSerial, SalespersonsSecurity.UserID, SalesPersonsDevicePermissions.AllowAddProspectiveCustomer, SalesPersons.TelephoneNo,ISNULL(AllowChangePriceInReturn,0) AS AllowChangePriceInReturn, AllowItemDiscInReturn ,AllowVouDiscInReturn,AllowUnloadOrder ,AllowMakeIssueItems,IssueItemsNextSerial,ISNULL(SalesInvoiceNextSerial_Credit,0) AS SalesInvoiceNextSerial_Credit,case when @ClientActive=97 then SalesPersons.DebitAccount  when @ClientActive=105 then SalesPersons.[VehicleId] else SalesPersons.SerialRef End,ISNULL(MaxLoadOrderAmount,0) AS MaxLoadOrderAmount,SalesPersons.SalesPersonType,
									 DebitCreditNoteNextSerial,AllowDebitCreditNote,ReceiveItemsNextSerial,1000,PaymentsOrdersNextSerial
			FROM            SalesPersons INNER JOIN
									 SalesPersonTransactionsSerials ON SalesPersons.CompanyID = SalesPersonTransactionsSerials.CompanyID AND SalesPersons.ID = SalesPersonTransactionsSerials.SalesPersonID INNER JOIN
									 SalesPersonsGroups ON SalesPersons.GroupID = SalesPersonsGroups.ID AND SalesPersons.CompanyID = SalesPersonsGroups.CompanyID INNER JOIN
									 SalesPersonsDevicePermissions ON SalesPersons.CompanyID = SalesPersonsDevicePermissions.CompanyID AND SalesPersons.PositionID = SalesPersonsDevicePermissions.PositionsID LEFT OUTER JOIN
									 SalespersonsSecurity ON SalesPersons.CompanyID = SalespersonsSecurity.CompanyID AND SalesPersons.ID = SalespersonsSecurity.SalespersonID
			WHERE        (SalesPersons.CompanyID = @CompNo) AND (SalesPersons.ID = @SalesmanNo) AND (SalesPersonTransactionsSerials.SerYear = YEAR(@SendDate))



End
END

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'OT_SalesmanMF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')



if @clientactive=149 ---///Mustadama Salesman Balance///---
begin
Declare @ExRate1 float =(select top(1)exrate from olives_BO..currenciesrate where companyid=@CompNo and currencyid=2 order by EntryDate desc)

Declare @ref1 int		
select @Ref1=Reference1 from salespersons where CompanyID=@CompNo and ID=@SalesmanNo
declare @Balance float
exec    [10.5.5.52] .db.[dbo].[Alpha_GetCashOnHand] @CompNo,@Ref1,@Balance output


select @Balance as Cashonhand
update osfa_DB..ot_SalesmanMF set cashonhand = @Balance*@ExRate1 where salesmanno=@SalesmanNo
END


-------- UPDATE Salesman Balance -----------------------
SET @BeginTime = Convert(varchar(20),GetDate(),108)

DECLARE @SalesmanBal float
SELECT @SalesmanBal = SUM(CurrBalance) FROM OSFA_DB.dbo.OT_CustomerMF WHERE CompNo = @CompNo and SalesmanNo = @SalesmanNo

UPDATE       OSFA_DB.dbo.OT_SalesmanMF
SET                SalesmanBalance = @SalesmanBal
WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'update SalesmanBalance in OT_SalesmanMF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')                                           
------- UPDATE SERIALS ------------------    

SET @BeginTime = Convert(varchar(20),GetDate(),108)

-----//// Orders //////////                  
DECLARE @OrderTakingNextSerial bigint
SET @OrderTakingNextSerial =(SELECT MAX(ISNULL(OrderNo,0))+1 FROM [OSFA_DB].[dbo].[OT_OrderHF] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (OrderYear = YEAR(@SendDate))) 
if @OrderTakingNextSerial IS NOT NULL
BEGIN
UPDATE    SalesPersonTransactionsSerials
SET              OrderTakingNextSerial = @OrderTakingNextSerial
WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

	UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET NextSerial=@OrderTakingNextSerial WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
END

-----//// CustStock //////////                  
DECLARE @CustStockNextSerial bigint
SET @CustStockNextSerial =(SELECT MAX(ISNULL(VouNo,0))+1 FROM [OSFA_DB].[dbo].[OT_CustStockHF] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (VouYear = YEAR(@SendDate))) 
if @CustStockNextSerial IS NOT NULL
BEGIN
UPDATE    SalesPersonTransactionsSerials
SET              CustStockNextSerial = @CustStockNextSerial
WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

	UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET CustStockNextSerial=@CustStockNextSerial WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
END

-----//// SalesInvoices //////////                  
DECLARE @SalesInvoiceNextSerial bigint

Declare @UseCreditInvoiceSerials as varchar(100) 
SET @UseCreditInvoiceSerials = [dbo].[Fun_GetSalesmanSysOpValue] (@CompNo,@SalesmanNo,470)


IF @UseCreditInvoiceSerials='1'
BEGIN
	SET @SalesInvoiceNextSerial =(SELECT MAX(ISNULL(VouNo,0))+1 FROM [OSFA_DB].[dbo].[OT_InvoiceHF] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (VouYear = YEAR(@SendDate)) AND ( VouType=1 ) AND CaCr=1) 
	if @SalesInvoiceNextSerial IS NOT NULL
	BEGIN
	UPDATE    SalesPersonTransactionsSerials
	SET              SalesInvoiceNextSerial = @SalesInvoiceNextSerial
	WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

		UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET InvNextSerial=@SalesInvoiceNextSerial WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
	END

	SET @SalesInvoiceNextSerial =(SELECT MAX(ISNULL(VouNo,0))+1 FROM [OSFA_DB].[dbo].[OT_InvoiceHF] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (VouYear = YEAR(@SendDate)) AND ( VouType=1 ) AND CaCr=0) 
	if @SalesInvoiceNextSerial IS NOT NULL
	BEGIN
	UPDATE    SalesPersonTransactionsSerials
	SET              [SalesInvoiceNextSerial_Credit] = @SalesInvoiceNextSerial
	WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

		UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET [SalesInvoiceNextSerial_Credit]=@SalesInvoiceNextSerial WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
	END

END
ELSE
BEGIN
	SET @SalesInvoiceNextSerial =(SELECT MAX(ISNULL(VouNo,0))+1 FROM [OSFA_DB].[dbo].[OT_InvoiceHF] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (VouYear = YEAR(@SendDate)) AND ( VouType=1 )) 
	if @SalesInvoiceNextSerial IS NOT NULL
	BEGIN
	UPDATE    SalesPersonTransactionsSerials
	SET              SalesInvoiceNextSerial = @SalesInvoiceNextSerial,SalesInvoiceNextSerial_Credit=0
	WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

		UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET InvNextSerial=@SalesInvoiceNextSerial ,SalesInvoiceNextSerial_Credit=0 WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
	END
END






-----//// ReturnSalesInvoices //////////                  
DECLARE @ReturnSalesNextSerial bigint
SET @ReturnSalesNextSerial =(SELECT MAX(ISNULL(VouNo,0))+1 FROM [OSFA_DB].[dbo].[OT_InvoiceHF] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (VouYear = YEAR(@SendDate)) AND ( VouType=2 )) 
if @ReturnSalesNextSerial IS NOT NULL
BEGIN
UPDATE    SalesPersonTransactionsSerials
SET              ReturnSalesNextSerial = @ReturnSalesNextSerial
WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

	UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET RetInvNextSerial=@ReturnSalesNextSerial WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
END

-----//// Reciepts //////////                  
DECLARE @ReceiptNextSerial bigint
SET @ReceiptNextSerial =(SELECT MAX(ISNULL(VouNo,0))+1 FROM [OSFA_DB].[dbo].[OT_Payments] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (VouYear = YEAR(@SendDate)) AND ( VouType=3 )) 
if @ReceiptNextSerial IS NOT NULL
BEGIN
UPDATE    SalesPersonTransactionsSerials
SET              ReceiptNextSerial = @ReceiptNextSerial
WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

	UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET RecNextSerial=@ReceiptNextSerial WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
END


-----//// Transfer Orders //////////                  
DECLARE @TransferOrderNextSerial bigint
SET @TransferOrderNextSerial =(SELECT MAX(ISNULL(OrderNo,0))+1 FROM [OSFA_DB].[dbo].[OT_ConsOrderHF] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (OrderYear = YEAR(@SendDate)) AND (VouType = 1)) 
if @TransferOrderNextSerial IS NOT NULL
BEGIN
UPDATE    SalesPersonTransactionsSerials
SET              TransferOrderNextSerial = @TransferOrderNextSerial
WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

	UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET ConsNextSerial=@TransferOrderNextSerial WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
	
END

-----//// Competitive Items //////////                  
DECLARE @CompetitiveItemsInfoNextSerial bigint
SET @CompetitiveItemsInfoNextSerial = (SELECT MAX(ISNULL(TrNo,0))+1 FROM [OSFA_DB].[dbo].[OT_CompetitveItemsDataHF] WHERE (CompanyID = @CompNo) AND (SalesPersons = @SalesmanNo) AND (TrYear = YEAR(@SendDate))) 
if @CompetitiveItemsInfoNextSerial IS NOT NULL
BEGIN
UPDATE    SalesPersonTransactionsSerials
SET              CompetitiveItemsInfoNextSerial = @CompetitiveItemsInfoNextSerial
WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

	UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET CompetitiveItemsInfoNextSerial=@CompetitiveItemsInfoNextSerial WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
	
END


-----//// UnLoadOrders //////////                  
DECLARE @UnLoadOrdersNextSerials bigint
SET @UnLoadOrdersNextSerials =(SELECT MAX(ISNULL(OrderNo,0))+1 FROM [OSFA_DB].[dbo].[OT_ConsOrderHF] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (OrderYear = YEAR(@SendDate)) AND (VouType = 2)) 
if @UnLoadOrdersNextSerials IS NOT NULL
BEGIN
UPDATE    SalesPersonTransactionsSerials
SET              UnLoadOrdersNextSerials = @UnLoadOrdersNextSerials
WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

	UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET UnLoadOrdersNextSerials=@UnLoadOrdersNextSerials WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
	
END  

if @ClientActive = 67
begin
if @UnLoadOrdersNextSerials IS NULL
BEGIN
select  @UnLoadOrdersNextSerials = isnull (UnLoadOrdersNextSerials,0) from  SalesPersonTransactionsSerials WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

UPDATE    SalesPersonTransactionsSerials
SET              UnLoadOrdersNextSerials = @UnLoadOrdersNextSerials +5000
WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET UnLoadOrdersNextSerials=@UnLoadOrdersNextSerials + 5000 WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
END 
end

-----//// Salesperson Stocktaking //////////      
DECLARE @SalesmanStockNextSerial bigint
SET @SalesmanStockNextSerial =(SELECT MAX(ISNULL(VouNo,0))+1 FROM [OSFA_DB].[dbo].[OT_SalesmanStockHF] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (VouYear = YEAR(@SendDate))) 
if @SalesmanStockNextSerial IS NOT NULL
BEGIN
UPDATE    SalesPersonTransactionsSerials
SET              SalesmanStockNextSerial = @SalesmanStockNextSerial
WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

	UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET SalesmanStockNextSerial=@SalesmanStockNextSerial WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
	
END     

-----//// Return Order //////////      
DECLARE @ReturnOrderNextSerial bigint
SET @ReturnOrderNextSerial =(SELECT MAX(ISNULL(VouNo,0))+1 FROM [OSFA_DB].[dbo].[OT_ReturnOrderHF] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (VouYear = YEAR(@SendDate))) 
if @ReturnOrderNextSerial IS NOT NULL
BEGIN
UPDATE    SalesPersonTransactionsSerials
SET              ReturnOrderNextSerial = @ReturnOrderNextSerial
WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

	UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET ReturnOrderNextSerial=@ReturnOrderNextSerial WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
	
END
-----//// Van Transfer //////////    
DECLARE @VanTransferNextSerial bigint
SET @VanTransferNextSerial =(SELECT MAX(ISNULL(OrderNo,0))+1 FROM [OSFA_DB].[dbo].[OT_VanTransferHF] WHERE (CompNo = @CompNo) AND (FromSalesman = @SalesmanNo) AND (OrderYear = YEAR(@SendDate))) 
if @VanTransferNextSerial IS NOT NULL
BEGIN
	UPDATE    SalesPersonTransactionsSerials
	SET              VanTransferNextSerial = @VanTransferNextSerial
	WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

	UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET VanTransferNextSerial=@VanTransferNextSerial WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
	
END

-----//// Sales Quotation //////////    
DECLARE @SalesQuotationNextSerial bigint
SET @SalesQuotationNextSerial =(SELECT MAX(ISNULL(OrderNo,0))+1 FROM [OSFA_DB].[dbo].[OT_SalesQuotationHF] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (OrderYear = YEAR(@SendDate))) 
if @SalesQuotationNextSerial IS NOT NULL
BEGIN
	UPDATE    SalesPersonTransactionsSerials
	SET              SalesQuotationNextSerial = @SalesQuotationNextSerial
	WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

	UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET SalesQuotationNextSerial=@SalesQuotationNextSerial WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
END

-----//// Items Replacment //////////    
DECLARE @ItemsReplacmentNextSerial bigint
SET @ItemsReplacmentNextSerial =(SELECT MAX(ISNULL(VouNo,0))+1 FROM [OSFA_DB].[dbo].[OT_ItemsReplacmentHF] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (VouYear = YEAR(@SendDate))  AND (VouType=1))
if @ItemsReplacmentNextSerial IS NOT NULL
BEGIN
	UPDATE    SalesPersonTransactionsSerials
	SET              ItemsReplacementNextSerial = @ItemsReplacmentNextSerial
	WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

	UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET ItemsReplacmentNextSerial=@ItemsReplacmentNextSerial WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
END
-----//// Issue Items //////////    
DECLARE @IssueItemsNextSerial bigint
SET @IssueItemsNextSerial =(SELECT MAX(ISNULL(OrderNo,0))+1 FROM [OSFA_DB].[dbo].OT_IssueItemsHF WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (OrderYear = YEAR(@SendDate))   )
if @IssueItemsNextSerial IS NOT NULL
BEGIN
	UPDATE    SalesPersonTransactionsSerials
	SET              IssueItemsNextSerial = @IssueItemsNextSerial
	WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

	UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET IssueItemsNextSerial=ISNULL(@IssueItemsNextSerial,0) WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
END


-----//// Debit Credit Note //////////    
DECLARE @DebitCreditNoteNextSerial bigint
SET @DebitCreditNoteNextSerial =(SELECT MAX(ISNULL(VouNo,0))+1 FROM [OSFA_DB].[dbo].OT_DebitCreditNoteTrans WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (VouYear = YEAR(@SendDate))   )
if @DebitCreditNoteNextSerial IS NOT NULL
BEGIN
	UPDATE    SalesPersonTransactionsSerials
	SET              DebitCreditNoteNextSerial = @DebitCreditNoteNextSerial
	WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

	UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET DebitCreditNoteNextSerial=ISNULL(@DebitCreditNoteNextSerial,0) WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
END


 
 


-----//// ReceiveItemsNextSerial //////////                  
DECLARE @ReceiveItemsNextSerial bigint
SET @ReceiveItemsNextSerial =(SELECT MAX(ISNULL(VouNo,0))+1 FROM [OSFA_DB].[dbo].[OT_InvoiceHF] WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo) AND (VouYear = YEAR(@SendDate)) AND ( VouType=16 )) 
if @ReceiveItemsNextSerial IS NOT NULL
BEGIN
UPDATE    SalesPersonTransactionsSerials
SET              ReceiveItemsNextSerial = @ReceiveItemsNextSerial
WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

	UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET ReceiveItemsNextSerial=@ReceiveItemsNextSerial WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
END







-----//// PaymentsOrdersNextSerial //////////                  
DECLARE @PaymentsOrdersNextSerial bigint
SET @PaymentsOrdersNextSerial = (SELECT MAX(ISNULL([OrderNo],0))+1 FROM PaymentsOrders WHERE (CompanyID = @CompNo) AND (SalespersonID = @SalesmanNo) AND ([OrderYear] = YEAR(@SendDate))) 
if @PaymentsOrdersNextSerial IS NOT NULL
BEGIN
	UPDATE    SalesPersonTransactionsSerials
	SET              PaymentsOrdersNextSerial = @PaymentsOrdersNextSerial
	WHERE     (SalesPersonID = @SalesmanNo) AND (CompanyID = @CompNo) AND (SalesPersonTransactionsSerials.SerYear=YEAR(@SendDate))

	UPDATE  [OSFA_DB].[dbo].[OT_SalesmanMF] SET PaymentsOrdersNextSerial=@PaymentsOrdersNextSerial WHERE (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
	
END







SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Update Salesman Serials On OT_SalesmanMF [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

SET @BeginTime = Convert(varchar(20),GetDate(),108)

IF @ClientActive = 28 -- ÇäæÇÑ ãßÉ
BEGIN
	UPDATE       OSFA_DB.dbo.OT_SalesmanMF
	SET             MonthlySalesTarget = 0, 
					MonthlySalesAmount = 0, 
					MonthlyCollectionTarget = 0, 
					MonthlyCollectionAmount = 0,
					TotalDamage = 0, 
					CustomerSalesCount = 0,
					CountOfAllCustomers = 0, 
					TotalAllWork = 0,	
					TotalWorkWithCustomer = 0				
	WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
END
ELSE
BEGIN 													
	UPDATE       OSFA_DB.dbo.OT_SalesmanMF
	SET                 MonthlySalesTarget = @SalesTarget, 
						MonthlySalesAmount = 854200, 
						MonthlyCollectionTarget = @CollectionTarget, 
						MonthlyCollectionAmount = @CollectionAmuont,
						TotalDamage = @DamageAmount, 
						CustomerSalesCount = @CustomerSalesCount,
						CountOfAllCustomers = @CountOfAllCustomers, 
						TotalAllWork = Round(26 * 8,0),	
						TotalWorkWithCustomer = @TotalWorkWithCustomer,
						AviItemsCount=@AviItemsCount,
						AllItemsCount=@AllItemsCount,
						TotalReturn=@TotalReturn	
									
	WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
END

SET @EndTime = Convert(varchar(20),GetDate(),108)
INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
VALUES (@CompNo,@SalesmanNo, GETDATE(), 'Update OT_SalesmanMF Targets Info [' + CAST(DATEDIFF(second,@BeginTime,@EndTime) AS varchar(50)) + ']')

IF @ClientActive = 161
BEGIN
	DECLARE @IsCashOpen int

	SELECT        Top 1  @IsCashOpen = CASE WHEN ActionID = '45' THEN 1 ELSE 0 END
	FROM            LogActionTransaction
	WHERE        (CompNo = @CompNo) AND (ActionID IN ('45', '46')) AND (CONVERT(DATE, TimeStamp) = Convert(DATE, @SendDate))
	ORDER BY TimeStamp DESC

	UPDATE       OSFA_DB.dbo.OT_SalesmanMF
	SET                IsCashOpen = ISNULL(@IsCashOpen,0)
	WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
END



/*
UPDATE       OSFA_DB.dbo.OT_SalesmanMF
SET                 MonthlySalesTarget = 1000, MonthlySalesAmount = 520, 
				    MonthlyCollectionTarget = 900, MonthlyCollectionAmount = 430,
					TotalAllWork = 200, TotalWorkWithCustomer = 123,
					TotalDamage = 45,
					CountOfAllCustomers = 1000, CustomerSalesCount = 200
WHERE        (CompNo = @CompNo) AND (SalesmanNo = @SalesmanNo)
*/
print 'end of send'
EXITPRO:
	UPDATE       SalesPersons
	SET                IsSendData = 0
	WHERE        (CompanyID = @CompNo) AND (ID = @SalesmanNo)

	INSERT INTO OT_SendLog(CompanyID, SalesmanNo, SysDate, LogText)
	VALUES(@CompNo, @SalesmanNo, getDate(), 'Finished')
	---Add
END

