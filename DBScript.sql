CREATE DATABASE PharmTrade;

GO

USE PharmTrade;

CREATE TABLE [dbo].[Goods] (
    [Id] INT IDENTITY(1,1) NOT NULL,
    [Name] NVARCHAR(50) NOT NULL,
    [SalePrice] DECIMAL(18,4) NOT NULL, 
    PRIMARY KEY CLUSTERED ([Id] ASC)
);



CREATE TABLE [dbo].[Currencies] (
    [Id] INT IDENTITY(0,1) NOT NULL,
    [Name] NVARCHAR(50) NOT NULL,
    PRIMARY KEY CLUSTERED ([Id] ASC)
);


CREATE TABLE [dbo].[ExchangeRates]
(
	[Id] INT IDENTITY(1,1) NOT NULL, 
    [CurrencyId] INT NOT NULL, 
    [Date] DATE NOT NULL, 
    [Rate] DECIMAL(18,4) NOT NULL,
	PRIMARY KEY CLUSTERED ([Id] ASC), 
    CONSTRAINT [FK_ExchangeRates_ToCurrencies] FOREIGN KEY ([CurrencyId]) REFERENCES [Currencies]([Id])
)

CREATE INDEX [IX_ExchangeRates_CurDate] ON [dbo].[ExchangeRates] ([Date], [CurrencyId])

CREATE TABLE [dbo].[Warehouses] (
    [Id] INT IDENTITY(1,1) NOT NULL,
    [Name] NVARCHAR(50) NOT NULL,
    PRIMARY KEY CLUSTERED ([Id] ASC)
);

CREATE TABLE [dbo].[Contractors] (
    [Id] INT IDENTITY(1,1) NOT NULL,
    [Name] NVARCHAR(50) NOT NULL,
    PRIMARY KEY CLUSTERED ([Id] ASC)
);

CREATE TABLE [dbo].[Incomes]
(
	[Id] INT NOT NULL PRIMARY KEY, 
    [Date] DATETIME NOT NULL, 
    [WarehouseId] INT NOT NULL, 
    [CurrencyId] INT NOT NULL, 
    [ContractorId] INT NOT NULL,
	CONSTRAINT [FK_Incomes_ToWarehouses] FOREIGN KEY ([WarehouseId]) REFERENCES [Warehouses]([Id]),
	CONSTRAINT [FK_Incomes_ToCurrencies] FOREIGN KEY ([CurrencyId]) REFERENCES [Currencies]([Id]),
	CONSTRAINT [FK_Incomes_ToContractors] FOREIGN KEY ([ContractorId]) REFERENCES [Contractors]([Id])
);

CREATE TABLE [dbo].[Outcomes]
(
	[Id] INT NOT NULL PRIMARY KEY, 
    [Date] DATETIME NOT NULL, 
    [WarehouseId] INT NOT NULL, 
    [ContractorId] INT NOT NULL,
	CONSTRAINT [FK_Outcomes_ToWarehouses] FOREIGN KEY ([WarehouseId]) REFERENCES [Warehouses]([Id]),
	CONSTRAINT [FK_Outcomes_ToContractors] FOREIGN KEY ([ContractorId]) REFERENCES [Contractors]([Id])
);

CREATE TABLE [dbo].[Balance]
(
	[Id] INT IDENTITY(1,1) NOT NULL PRIMARY KEY, 
    [WarehouseId] INT NOT NULL, 
    [GoodId] INT NOT NULL, 
    [Count] INT NOT NULL, 
    [Amount] DECIMAL(18,4) NOT NULL,
	CONSTRAINT [FK_Balance_ToWarehouses] FOREIGN KEY ([WarehouseId]) REFERENCES [Warehouses]([Id]),
	CONSTRAINT [FK_Balance_ToGoods] FOREIGN KEY ([GoodId]) REFERENCES [Goods]([Id]),
	CONSTRAINT [CHK_Count] CHECK ([Count]>=(0))
);

CREATE INDEX [IX_Balance_WarehouseGood] ON [dbo].[Balance] ([WarehouseId], [GoodId])


CREATE TABLE [dbo].[IncomeSpecification]
(
	[Id] INT IDENTITY(1,1) NOT NULL PRIMARY KEY, 
	[IncomeId] INT NOT NULL, 
    [LineNumber] INT NOT NULL, 
    [GoodId] INT NOT NULL, 
    [Count] INT NOT NULL, 
    [Price] DECIMAL(18,4) NOT NULL, 
    [Amount] DECIMAL(18,4) NOT NULL,
	CONSTRAINT [FK_IncomeSpecification_ToIncomes] FOREIGN KEY ([IncomeId]) REFERENCES [Incomes]([Id]),
	CONSTRAINT [FK_IncomeSpecification_ToGoods] FOREIGN KEY ([GoodId]) REFERENCES [Goods]([Id])
);

CREATE INDEX [IX_IncomeSpecification_IncomeId] ON [dbo].[IncomeSpecification] ([IncomeId])
GO

USE PharmTrade;
GO

CREATE TRIGGER [dbo].[Trigger_IncomeSpecification]
ON [dbo].[IncomeSpecification]
FOR INSERT
AS
BEGIN

	DECLARE @Rate DECIMAL(18,4), @Date DATE, @CurrencyId INT
	SET @Rate = 1
	SELECT @CurrencyId = CurrencyId, @Date=CAST(Date AS DATE) FROM inserted AS i INNER JOIN Incomes AS inc ON inc.[Id] = i.[IncomeId]
	IF(@CurrencyId<>0)
	SELECT @Rate = [Rate] FROM [dbo].[ExchangeRates] AS e WHERE e.CurrencyId = @CurrencyId AND e.Date = @Date
			
	MERGE Balance AS b
	USING (SELECT SUM(i.[Count]) as [Count], SUM(i.[Amount]) as [Amount], i.[GoodId], inc.[WarehouseId] 
			FROM inserted AS i 
					INNER JOIN Incomes AS inc ON inc.[Id] = i.[IncomeId]
			GROUP BY i.[GoodId], inc.[WarehouseId] 
			) AS new
	ON (b.[WarehouseId] = new.[WarehouseId] AND b.[GoodId] = new.[GoodId])
	WHEN NOT MATCHED THEN
		INSERT ([WarehouseId], [GoodId], [Count], [Amount]) 
		VALUES (new.[WarehouseId], new.[GoodId], new.[Count], new.[Amount]*@Rate)
	WHEN MATCHED THEN
		UPDATE SET b.[Count] = b.[Count] + new.[Count], b.[Amount] = b.[Amount] + new.[Amount]*@Rate;

END
GO

USE PharmTrade;
GO

CREATE TABLE [dbo].[OutcomeSpecification]
(
	[Id] INT IDENTITY(1,1) NOT NULL PRIMARY KEY, 
	[OutcomeId] INT NOT NULL, 
    [LineNumber] INT NOT NULL, 
    [GoodId] INT NOT NULL, 
    [Count] INT NOT NULL, 
    [Price] DECIMAL NULL, 
    [Amount] DECIMAL NULL,
	CONSTRAINT [FK_OutcomeSpecification_ToOutcomes] FOREIGN KEY ([OutcomeId]) REFERENCES [Outcomes]([Id]),
	CONSTRAINT [FK_OutcomeSpecification_ToGoods] FOREIGN KEY ([GoodId]) REFERENCES [Goods]([Id])
);

CREATE INDEX [IX_OutcomeSpecification_OutcomeId] ON [dbo].[OutcomeSpecification] ([OutcomeId]);
GO

USE PharmTrade;
GO

CREATE TRIGGER [dbo].[Trigger_OutcomeSpecification]
ON [dbo].[OutcomeSpecification]
FOR INSERT
AS
BEGIN
	DECLARE @GoodId VARCHAR
	DECLARE @tempTable TABLE(GoodId INT)
	INSERT INTO @tempTable
	SELECT i.GoodId FROM Outcomes AS o
			INNER JOIN	inserted AS i ON o.[Id]=i.[OutcomeId]
			LEFT JOIN	Balance AS b ON b.[GoodId]=i.[GoodId] AND b.[WarehouseId]=o.[WarehouseId]
			WHERE (b.[Count]-i.[Count])<0 OR b.[GoodId] IS NULL;
	SELECT @GoodId = CONVERT(VARCHAR,GoodId) FROM @tempTable;

	IF exists (select * from @tempTable)
		RAISERROR(N'The warehouse does not contain required amount of good with id = %s', 16, 1, @GoodId);

	MERGE Balance AS b
	USING (SELECT SUM(i.[Count]) as [Count], SUM(i.[Amount]) as [Amount], i.[GoodId], o.[WarehouseId] 
			FROM inserted AS i 
					INNER JOIN Outcomes AS o ON o.[Id] = i.[OutcomeId]
			GROUP BY i.[GoodId], o.[WarehouseId] 
			) AS new
	ON (b.[WarehouseId] = new.[WarehouseId] AND b.[GoodId] = new.[GoodId])
	WHEN MATCHED THEN
		UPDATE SET b.[Amount] = b.[Amount] - new.[Count]*(b.[Amount]/b.[Count]), b.[Count] = b.[Count] - new.[Count];
		
END

GO

USE PharmTrade;
GO

CREATE PROCEDURE [dbo].[Save_Income] (@data XML)

AS 
DECLARE @ErrorMessage NVARCHAR(4000);
DECLARE @ErrorSeverity INT;
DECLARE @ErrorState INT;

BEGIN TRANSACTION
	DECLARE @IncId INT
	SELECT TOP 1 @IncId = Node.Data.value('(/Doc/@Id)[1]','INT') FROM @data.nodes('/Doc') AS Node(Data);

	BEGIN TRY 
		INSERT INTO [dbo].[Incomes]([Id], [Date], [WarehouseId], [CurrencyId], [ContractorId])
		SELECT
			[Id] = Node.Data.value('(/Doc/@Id)[1]','INT'),
			[Date] = Node.Data.value('(/Doc/@Date)[1]','DATETIME'),
			[WarehouseId] = Node.Data.value('(/Doc/@WarehouseId)[1]','INT'),
			[CurrencyId] = Node.Data.value('(/Doc/@CurrencyId)[1]','INT'),
			[ContractorId] = Node.Data.value('(/Doc/@ContractorId)[1]','INT')
		FROM 
			@data.nodes('/Doc') AS Node(Data);
	END TRY  
	BEGIN CATCH 
	SELECT 
        @ErrorMessage = ERROR_MESSAGE(),
        @ErrorSeverity = ERROR_SEVERITY(),
        @ErrorState = ERROR_STATE();
		GOTO ERR_HANDLER;
	END CATCH; 

	BEGIN TRY 
		INSERT INTO [dbo].[IncomeSpecification]([IncomeId], [LineNumber], [GoodId], [Count], [Price], [Amount])
		SELECT
			[IncomeId] = @IncId,
			[LineNumber] = Node.Data.value('(@Id)[1]','INT'),
			[GoodId] = Node.Data.value('(@GoodId)[1]','INT'),
			[Count] = Node.Data.value('(@Count)[1]','INT'),
			[Price] = Node.Data.value('(@Price)[1]','INT'),
			[Amount] = Node.Data.value('(@Amount)[1]','INT')

		FROM 
			@data.nodes('/Doc/Line') AS Node(Data);
	END TRY  
	BEGIN CATCH 
	SELECT 
        @ErrorMessage = ERROR_MESSAGE(),
        @ErrorSeverity = ERROR_SEVERITY(),
        @ErrorState = ERROR_STATE();
		GOTO ERR_HANDLER;
	END CATCH;  
COMMIT TRANSACTION;

ERR_HANDLER:
IF(@@TRANCOUNT > 0) 
	BEGIN
	ROLLBACK TRANSACTION;
	PRINT N'Rolling back the transaction. See details in error message below.';
	RAISERROR (@ErrorMessage,@ErrorSeverity, @ErrorState);
	END;

GO

USE PharmTrade;
GO

CREATE PROCEDURE [dbo].[Save_Outcome] (@data XML)

AS 
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;  

DECLARE @ErrorMessage NVARCHAR(4000);
DECLARE @ErrorSeverity INT;
DECLARE @ErrorState INT;

BEGIN TRANSACTION
	DECLARE @OutcomeId INT
	SELECT TOP 1 @OutcomeId = Node.Data.value('(/Doc/@Id)[1]','INT') FROM @data.nodes('/Doc') AS Node(Data);

	BEGIN TRY 
		INSERT INTO [dbo].[Outcomes]([Id], [Date], [WarehouseId], [ContractorId])
		SELECT
			[Id] = Node.Data.value('(/Doc/@Id)[1]','INT'),
			[Date] = Node.Data.value('(/Doc/@Date)[1]','DATETIME'),
			[WarehouseId] = Node.Data.value('(/Doc/@WarehouseId)[1]','INT'),
			[ContractorId] = Node.Data.value('(/Doc/@ContractorId)[1]','INT')
		FROM 
			@data.nodes('/Doc') AS Node(Data);
	END TRY  
	BEGIN CATCH 
	SELECT 
        @ErrorMessage = ERROR_MESSAGE(),
        @ErrorSeverity = ERROR_SEVERITY(),
        @ErrorState = ERROR_STATE();
		GOTO ERR_HANDLER;
	END CATCH; 

	BEGIN TRY 
		INSERT INTO [dbo].[OutcomeSpecification]([OutcomeId], [LineNumber], [GoodId], [Count], [Price], [Amount])
		SELECT
			[OutcomeId] = @OutcomeId,
			[LineNumber] = Node.Data.value('(@Id)[1]','INT'),
			[GoodId] = Node.Data.value('(@GoodId)[1]','INT'),
			[Count] = Node.Data.value('(@Count)[1]','INT'),
			[Price] = Node.Data.value('(@Price)[1]','INT'),
			[Amount] = Node.Data.value('(@Amount)[1]','INT')

		FROM 
			@data.nodes('/Doc/Line') AS Node(Data);
	END TRY  
	BEGIN CATCH 
	SELECT 
        @ErrorMessage = ERROR_MESSAGE(),
        @ErrorSeverity = ERROR_SEVERITY(),
        @ErrorState = ERROR_STATE();
		GOTO ERR_HANDLER;
	END CATCH;  

	DELETE FROM [dbo].[Balance] WHERE [Count]=0;

COMMIT TRANSACTION;

SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;  

ERR_HANDLER:
IF(@@TRANCOUNT > 0) 
	BEGIN
	ROLLBACK TRANSACTION;
	PRINT N'Rolling back the transaction. See details in error message below.';
	RAISERROR (@ErrorMessage,@ErrorSeverity, @ErrorState);
	END;

GO

--filling test data

USE PharmTrade;
GO

INSERT INTO [dbo].[Goods] ([Name], [SalePrice])
VALUES (N'Йод', 50), (N'Зеленка', 60), (N'Витамишки', 20), (N'Марля', 15), (N'Гидроперит', 70),
(N'Терафлю', 150), (N'Аспирин', 100), (N'Имодиум', 110), (N'Фастум-гель', 220), (N'Стрепсилс', 180);

SET IDENTITY_INSERT [dbo].[Currencies] ON
INSERT INTO [dbo].[Currencies] ([Id], [Name])
VALUES (0, N'Рубль'), (1, N'Доллар'), (2, N'Евро');
SET IDENTITY_INSERT [dbo].[Currencies] OFF

INSERT INTO [dbo].[ExchangeRates] ([CurrencyId], [Date], [Rate])
VALUES (1, '2018-01-03', 57.5), (2, '2018-01-03', 68.5),
(1, '2018-01-04', 57.6), (2, '2018-01-04', 68.6),
(1, '2018-01-05', 57.7), (2, '2018-01-05', 68.7);

INSERT INTO [dbo].[Warehouses] ([Name])
VALUES (N'Безымянка'), (N'Заречный'), (N'Южный');

INSERT INTO [dbo].[Contractors] ([Name])
VALUES (N'ООО "Вектор"'), (N'ООО "Палитра"'), (N'ООО "Радуга"');

DECLARE @xmlData xml =
'<Doc Id="1" Date="2018-01-04T00:00:00" WarehouseId="1" CurrencyId="1" ContractorId="1">
<Line Id="1" GoodId="6" Count="2" Price="1" Amount="2"/>
<Line Id="2" GoodId="7" Count="3" Price="1" Amount="3"/>
</Doc>';

EXECUTE Save_Income @xmlData;

SET @xmlData =
'<Doc Id="1" Date="2018-01-04T07:42:00" WarehouseId="1" ContractorId="2">
<Line Id="1" GoodId="7" Count="3" Price="1" Amount="3"/>
</Doc>';

EXECUTE Save_Outcome @xmlData;