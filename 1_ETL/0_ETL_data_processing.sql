-- =========================================================================
-- ETL-Pipeline: Staging -> Cleansing -> Data Mart mit Fehlerbehandlung
-- =========================================================================

DECLARE @GezählteZeilen INT = 0; -- Eigener "Tresor" für Zeilen (Start: 0)

BEGIN TRY
    BEGIN TRANSACTION; -- 1. Transaktion starten (für sicheres Rollback)

        -- -----------------------------------------------------------------
        -- SCHRITT 1: STAGING (Daten roh laden)
        -- -----------------------------------------------------------------
        TRUNCATE TABLE Staging_Sales;
        
        INSERT INTO Staging_Sales (RawData)
        SELECT RawData FROM Source_Files;
        
        -- Systemvariablen-Schnappschuss sichern:
        SET @GezählteZeilen = @@ROWCOUNT; 
        -- Wert von @@ROWCOUNT          : (Anzahl geladener Rohdaten)
        -- Wert von @GezählteZeilen : (Gleicher Wert, sicher im Tresor)
        PRINT '1. Staging erfolgreich: ' + CAST(@GezählteZeilen AS VARCHAR(10)) + ' Zeilen geladen.';


        -- -----------------------------------------------------------------
        -- SCHRITT 2: CLEANSING (Bereinigung / Transformation)
        -- -----------------------------------------------------------------
        -- Wir rufen eine fertige Stored Procedure für die Datenbereinigung auf
        EXEC sp_CleanseSalesData;
        
        -- Falls die Stored Procedure intern kein SET @var = @@ROWCOUNT macht,
        -- können wir den @@ROWCOUNT direkt nach dem EXEC abgreifen:
        SET @GezählteZeilen = @@ROWCOUNT;
        PRINT '2. Cleansing abgeschlossen. Betroffene Zeilen: ' + CAST(@GezählteZeilen AS VARCHAR(10));


        -- -----------------------------------------------------------------
        -- SCHRITT 3: DATA MART (DM) (Laden in die Zieltabelle)
        -- -----------------------------------------------------------------
        INSERT INTO DM_FactSales (CustomerID, ProductID, Amount)
        SELECT CustomerID, ProductID, Amount 
        FROM Staging_Sales 
        WHERE IsValid = 1;

        SET @GezählteZeilen = @@ROWCOUNT;
        PRINT '3. Data Mart erfolgreich aktualisiert: ' + CAST(@GezählteZeilen AS VARCHAR(10)) + ' Zeilen geschrieben.';

    COMMIT TRANSACTION; -- Alles lief perfekt -> Änderungen dauerhaft speichern!
    PRINT 'ETL-Pipeline komplett erfolgreich beendet.';

END TRY

BEGIN CATCH
    -- -----------------------------------------------------------------
    -- CATCH-BLOCK: Greift ein, sobald im TRY-Block ein Fehler passiert
    -- -----------------------------------------------------------------
    
    -- Wenn eine Transaktion offen ist, machen wir alles rückgängig (Datenmüll verhindern!)
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION; 

    -- Fehlermeldung des Systems abfangen
    DECLARE @FehlerText NVARCHAR(4000) = ERROR_MESSAGE();
    
    PRINT 'FEHLER in der ETL-Pipeline aufgetreten!';
    PRINT 'Fehlerdetails: ' + @FehlerText;
    
    -- Hier könnte man den Fehler jetzt in eine Audit-Log-Tabelle schreiben
END CATCH;