USE [KD_Safilin]
GO
/****** Object:  StoredProcedure [dbo].[VisoResult]    Script Date: 23.03.2022 18:00:32 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[VisoResult] 
as

/*----------------------------------------------------------------/
/   Zapytanie ma na celu spisać czas wejścia (1) oraz wyjścia (0) 
/   oraz ID osoby. 
/ 
/   SUBSTRING ma na celu wyłonienie WE/WY na podstawie nazwy 
/   przejścia w VISO. Obecnie dostępne są:
/   SZCZYTNO:
/   - P_SZC_WE_BRAMA_L1
/   - P_SZC_WE_BRAMA_L2
/   - P_SZC_WY_BRAMA_R1
/   - P_SZC_WY_BRAMA_R2
/   - P_SZC_WE_SEKRETARIAT
/   - P_SZC_WY_SEKRETARIAT
/   MIŁAKOWO:
/   - P_MIL_WE_GORA
/   - P_MIL_WY_GORA
/	- P_MIL_WE_BRAMA
/	- P_MIL_WY_BRAMA
/   - P_MIL_WE_SEKRETARIAT
/   - P_MIL_WY_SEKRETARIAT
/
/   Powyższe przejścia zaczytywane są do Enovy
/
/   Przejścia, które nie są uwzględniane to:
/   SZCZYTNO:
/   - PI_KORYTARZ_WE
/   - PI_KORYTARZ_WY
/
/----------------------------------------------------------------*/


BEGIN
	SET NOCOUNT ON;

-- tworzenie tymczasowej tablicy 
	DECLARE @viso_table table 
	(
		LoggedOn nvarchar(20),
		V smallint,
		PID smallint
	)

-- wrzucenie do tablicy tymczasowej danych z rejestratorów
	INSERT INTO @viso_table (LoggedOn, V, PID)
	SELECT DISTINCT
	(LEFT(RTRIM(CONVERT(DATETIMEOFFSET, t1.[LoggedOn])), 19)) as LoggedOn,
	(CAST ( CASE 
			WHEN (LEFT(SUBSTRING(t2.[Name], 7,2),2) = 'WE'and t1.[Option]='0000000015') THEN 5 -- powrót (prywatny)
			WHEN (LEFT(SUBSTRING(t2.[Name], 7,2),2) = 'WY'and t1.[Option]='0000000012') THEN 4 -- wyjście prywatne
			WHEN (LEFT(SUBSTRING(t2.[Name], 7,2),2) = 'WE'and t1.[Option]='0000000014') THEN 3 -- powrót (służbowy)
			WHEN (LEFT(SUBSTRING(t2.[Name], 7,2),2) = 'WY' and t1.[Option]='0000000004') THEN 2	-- wyjście służbowe
			WHEN (LEFT(SUBSTRING(t2.[Name], 7,2),2) = 'WE' and t1.[Option]='          ') THEN 1
			WHEN (LEFT(SUBSTRING(t2.[Name], 7,2),2) = 'WY' and t1.[Option]='          ') THEN 0
			END AS smallint)) as V,
	(CAST(t1.[PersonID] AS smallint)) as PID

	FROM
	[KD_Safilin].[dbo].[EventLogEntries] as t1, 
	[KD_Safilin].[dbo].[AccessPoints] as t2, 
	[KD_Safilin].[dbo].[AccessUserPersons] as t3

	WHERE
	(t1.[Function] = 151 or t1.[Function] = 153 or t1.[Function] = 155) and 
	t1.personid is not null and 
	t1.SourceID = t2.ID and
	t1.[PersonID] = t3.[id] and
	t2.[Name] LIKE 'P_%' and
	t1.[LoggedOn] > CURRENT_TIMESTAMP - 0.0416666666666667 and 
	(CAST ( CASE 
			WHEN (LEFT(SUBSTRING(t2.[Name], 7,2),2) = 'WE'and t1.[Option]='0000000015') THEN 5 -- powrót (prywatny)
			WHEN (LEFT(SUBSTRING(t2.[Name], 7,2),2) = 'WY'and t1.[Option]='0000000012') THEN 4 -- wyjście prywatne
			WHEN (LEFT(SUBSTRING(t2.[Name], 7,2),2) = 'WE'and t1.[Option]='0000000014') THEN 3 -- powrót (służbowy)
			WHEN (LEFT(SUBSTRING(t2.[Name], 7,2),2) = 'WY' and t1.[Option]='0000000004') THEN 2	-- wyjście służbowe
			WHEN (LEFT(SUBSTRING(t2.[Name], 7,2),2) = 'WE' and t1.[Option]='          ') THEN 1
			WHEN (LEFT(SUBSTRING(t2.[Name], 7,2),2) = 'WY' and t1.[Option]='          ') THEN 0
				END AS smallint)) IS NOT NULL
	

-- zmienne wykorzystywane przy wskaźnikach
	DECLARE @C_LoggedOn nvarchar(20)
	DECLARE @C_V smallint
	DECLARE @C_PID smallint

	DECLARE @C_PreviousV smallint
	DECLARE @C_PreviousPID smallint 
	DECLARE @C_PreviousLoggedOn nvarchar(20)

-- tworzenie kursora
	DECLARE viso_cursor CURSOR FOR 
	SELECT * from @viso_table

	OPEN viso_cursor
	FETCH NEXT FROM viso_cursor INTO @C_LoggedOn, @C_V, @C_PID
	
	WHILE @@FETCH_STATUS = 0
		BEGIN
		-- na samym wstępnie należy przypisać obecne wartości do poprzednich, aby odwoływać się do nich w późniejszych rekordach
			IF (@C_PreviousLoggedOn IS NULL AND @C_PreviousPID IS NULL AND @C_PreviousV IS NULL)
				BEGIN
--					PRINT 'USTAWIENIE @C_PreviousLoggedOn , @C_PreviousPID, @C_PreviousV'
					SET @C_PreviousLoggedOn = @C_LoggedOn
					SET @C_PreviousPID = @C_PID
					SET @C_PreviousV = @C_V
/*
--===== OUTPUT CHECK ======================================
					PRINT '@C_PreviousLoggedOn : ' + @C_PreviousLoggedOn + ' | @C_PreviousPID: ' + CAST(@C_PreviousPID as varchar)+ ' | @C_PreviousV: ' + CAST(@C_PreviousV as varchar) +
						  ' | @C_LoggedOn : ' + @C_LoggedOn + ' | @C_PID: ' + CAST(@C_PID as varchar)+ ' | @C_V: ' + CAST(@C_V as varchar);
--=========================================================
*/
					FETCH NEXT FROM viso_cursor INTO @C_LoggedOn, @C_V,@C_PID
					CONTINUE;
				END
			-- sprawdzenie, czy ID osoby oraz czy status (wejście/wyjście) jest takie samo jak poprzednio
				IF (@C_PreviousPID = @C_PID AND @C_PreviousV = @C_V)
				BEGIN
				-- niwelowanie długiego przytrzymywania kart
					IF( (SELECT DATEDIFF(second, @C_PreviousLoggedOn, @C_LoggedOn)) <= 30)
					BEGIN
/*
--===== OUTPUT CHECK ======================================
						PRINT '@C_PreviousLoggedOn : ' + @C_PreviousLoggedOn + ' | @C_PreviousPID: ' + CAST(@C_PreviousPID as varchar)+ ' | @C_PreviousV: ' + CAST(@C_PreviousV as varchar) +
						' | @C_LoggedOn : ' + @C_LoggedOn + ' | @C_PID: ' + CAST(@C_PID as varchar)+ ' | @C_V: ' + CAST(@C_V as varchar) + ' | WEJŚCIE W PĘTLĘ USUWANIA';
--=========================================================
*/
						SET @C_PreviousLoggedOn = @C_LoggedOn
						SET @C_PreviousPID = @C_PID
						SET @C_PreviousV = @C_V;

						DELETE FROM @viso_table WHERE CURRENT OF viso_cursor;

--						PRINT ' ! USUNIĘTO REKORD !';

						FETCH NEXT FROM viso_cursor INTO @C_LoggedOn, @C_V,@C_PID
						CONTINUE;

					END
/*
--===== OUTPUT CHECK ======================================
					PRINT '@C_PreviousLoggedOn : ' + @C_PreviousLoggedOn + ' | @C_PreviousPID: ' + CAST(@C_PreviousPID as varchar)+ ' | @C_PreviousV: ' + CAST(@C_PreviousV as varchar) +
						  ' | @C_LoggedOn : ' + @C_LoggedOn + ' | @C_PID: ' + CAST(@C_PID as varchar)+ ' | @C_V: ' + CAST(@C_V as varchar);
--=========================================================
*/
					SET @C_PreviousLoggedOn = @C_LoggedOn
					SET @C_PreviousPID = @C_PID
					SET @C_PreviousV = @C_V

					FETCH NEXT FROM viso_cursor INTO @C_LoggedOn, @C_V,@C_PID
					CONTINUE;
				END

				IF(@C_PreviousPID = @C_PID AND (@C_PreviousV = 2 OR @C_PreviousV = 5 OR @C_PreviousV = 4 OR @C_PreviousV = 3))
				BEGIN
/*
--===== OUTPUT CHECK ======================================
					PRINT '@C_PreviousLoggedOn : ' + @C_PreviousLoggedOn + ' | @C_PreviousPID: ' + CAST(@C_PreviousPID as varchar)+ ' | @C_PreviousV: ' + CAST(@C_PreviousV as varchar) +
						  ' | @C_LoggedOn : ' + @C_LoggedOn + ' | @C_PID: ' + CAST(@C_PID as varchar)+ ' | @C_V: ' + CAST(@C_V as varchar) + ' | WEJŚCIE W PĘTLĘ USUWANIA';
--=========================================================
*/
					SET @C_PreviousLoggedOn = @C_LoggedOn
					SET @C_PreviousPID = @C_PID
					SET @C_PreviousV = @C_V;

					DELETE FROM @viso_table WHERE CURRENT OF viso_cursor;

--					PRINT ' ! USUNIĘTO REKORD ZWIĄZANY Z WYJŚCIEM/WEJŚCIEM SŁUŻBOWYM/PRYWATNYM!';

					FETCH NEXT FROM viso_cursor INTO @C_LoggedOn, @C_V,@C_PID
					CONTINUE;
				END
/*	
--===== OUTPUT CHECK ======================================
			PRINT '@C_PreviousLoggedOn : ' + @C_PreviousLoggedOn + ' | @C_PreviousPID: ' + CAST(@C_PreviousPID as varchar)+ ' | @C_PreviousV: ' + CAST(@C_PreviousV as varchar) +
				  ' | @C_LoggedOn : ' + @C_LoggedOn + ' | @C_PID: ' + CAST(@C_PID as varchar)+ ' | @C_V: ' + CAST(@C_V as varchar);
--=========================================================
*/
			SET @C_PreviousLoggedOn = @C_LoggedOn
			SET @C_PreviousPID = @C_PID
			SET @C_PreviousV = @C_V

			FETCH NEXT FROM viso_cursor INTO @C_LoggedOn, @C_V, @C_PID
		END
	CLOSE viso_cursor
	DEALLOCATE viso_cursor 

	SELECT * FROM @viso_table order by LoggedOn desc

END



/*============================================================*/
/*		  POBIERANIE WYNIKÓW WEDŁUG PRZEDZIAŁU CZASOWEGO	  */
/*============================================================*/

/*
BEGIN

SET NOCOUNT ON;

SELECT DISTINCT 
LEFT(RTRIM(CONVERT(DATETIMEOFFSET, T1.[LoggedOn])), 19) as LoggedOn,
CAST ( CASE 
		WHEN LEFT(SUBSTRING(t2.[Name], 7,2),2) = 'WE' THEN 1
		WHEN LEFT(SUBSTRING(t2.[Name], 7,2),2) = 'WY' THEN 0
			END AS bit) as V,
CAST(t1.[PersonID] AS smallint) as PID
from 
[KD_Safilin].[dbo].[EventLogEntries] as T1, 
[KD_Safilin].[dbo].[AccessPoints] as T2, 
[KD_Safilin].[dbo].[AccessUserPersons] as t3

where 
t1.[Function] = 151 and 
t1.personid is not null and 
t1.SourceID = t2.ID and
T1.[PersonID] = t3.[id] and
t2.[Name] LIKE 'P_%' and
(t1.[LoggedOn] between '2021-07-21 00:00:00.000' and '2021-07-23 12:00:00.000') and
(CAST ( CASE 
		WHEN LEFT(SUBSTRING(t2.[Name], 7,2),2) = 'WE' THEN 1
		WHEN LEFT(SUBSTRING(t2.[Name], 7,2),2) = 'WY' THEN 0
			END AS bit)) IS NOT NULL
order by LoggedOn desc

END

*/
/*============================================================*/
