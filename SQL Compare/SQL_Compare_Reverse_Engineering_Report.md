# Reverse Engineering Report — "SQL Compare" (Olives Drift Tool)

**Analyzed path:** `/media/alaa/data/olives/apps/drift-tool/SQL Compare/`
**Analysis method:** static analysis — PE header inspection, Unicode string extraction, full IL decompilation with ILSpy 8.2 (VB.NET → C# view), dependency DLL decompilation, `.config` analysis.
**Report date:** 2026-08-22

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [File Inventory](#2-file-inventory)
3. [Technology Stack](#3-technology-stack)
4. [Application Architecture](#4-application-architecture)
5. [User Interface Walkthrough](#5-user-interface-walkthrough)
6. [Configuration System](#6-configuration-system)
7. [Database Metadata Queries (the core SQL)](#7-database-metadata-queries-the-core-sql)
8. [Feature Deep-Dives](#8-feature-deep-dives)
   - 8.1 Compare workflow
   - 8.2 Object synchronization ("Run Script")
   - 8.3 Column diff & sync
   - 8.4 PK / FK compare
   - 8.5 All SPs & Functions tab
   - 8.6 Copy Data engine
   - 8.7 Save Script generators
   - 8.8 ObjectScript viewer dialog
   - 8.9 Error reporting dialog
9. [The SQL-DMO Legacy Layer](#9-the-sql-dmo-legacy-layer)
10. [Connection Handling](#10-connection-handling)
11. [Themes & Branding](#11-themes--branding)
12. [Security Findings](#12-security-findings)
13. [Defects & Quirks Found in Code](#13-defects--quirks-found-in-code)
14. [Runtime Requirements & How To Run It Today](#14-runtime-requirements--how-to-run-it-today)
15. [Relationship to the Olives Repository](#15-relationship-to-the-olives-repository)
16. [Modern Rewrite Guidance](#16-modern-rewrite-guidance)
17. [Reverse Engineering Methodology Used](#17-reverse-engineering-methodology-used)

---

## 1. Executive Summary

**"SQL Compare" v2.2.0.0** is an in-house, 32-bit **Visual Basic .NET WinForms desktop utility** that performs **schema drift detection and one-way synchronization between two Microsoft SQL Server databases** (source "Database 1" → target "Database 2"). It was built for maintaining customer-specific forks of the **Olives ERP image database** — the shipped config points at `Olives_Images` (server `10.0.10.105`) vs `Olives_Images_AlMalak` (local `.`), i.e., syncing a base product DB into a customer-tweaked copy (or vice versa).

It is *not* Redgate's commercial "SQL Compare" — it is an original in-house clone (assembly company "M22", copyright 2010, DevExpress v12.2 UI libraries ≈ 2012, EXE last rebuilt Feb 2020).

**In one sentence:** it snapshots the catalogs of two SQL Server databases using legacy system tables (`dbo.sysobjects`, `syscolumns`, …), shows what exists in one but not the other (objects, columns, primary keys, foreign keys, stored procedures, functions, user-defined table types), lets the operator tick rows, then generates T-SQL (`CREATE` / `ALTER TABLE ADD|ALTER COLUMN` / `DROP+CREATE`) and either **executes it live against Database 2 via the ancient SQL-DMO COM API**, or saves it as `.sql` files. A sixth tab bulk-copies **table data** row-by-row for menu/page configuration tables.

Key capabilities at a glance:

| Capability | Mechanism |
|---|---|
| Detect objects missing in either DB | Set difference over `sysobjects` + `sys.table_types` keyed on `(name, uid)` |
| Detect new/modified columns | Keyed tuple `(table, uid, column, type, length)` |
| Detect new/modified PKs / FKs | Keyed tuples over `sysindexes`/`sysindexkeys`/`sysforeignkeys` |
| View any object's script | SQL-DMO `Script()` in read-only viewer dialog |
| Sync selected objects DB1→DB2 | SQL-DMO scripting + `ExecuteImmediate` on target |
| Add/alter columns incl. default value backfill | Generated `ALTER TABLE` + optional `UPDATE` |
| Copy data of menu/page tables | Row-by-row generated `INSERT`s (with `UPDATE`-by-key fallback) |
| Export scripts | `.sql` (Unicode) and `.rtf` error reports |

---

## 2. File Inventory

| File | Size | Type / Role |
|---|---:|---|
| `SQL Compare.exe` | 358 KB | **Main application.** .NET Framework (net35 target) WinForms executable, VB.NET, assembly version 2.2.0.0, mtime Feb 2020 |
| `SQL Compare.exe.config` | 1.7 KB | .NET config: diagnostics logging stub + `appSettings` holding saved connections (**plaintext credentials**) and theme |
| `SQLDetection.dll` | 40 KB | Custom reusable `SQLDetection.SQLDetection : UserControl` — the server/database picker widget used twice on the main form |
| `Interop.SQLDMO.dll` | 950 KB | Primary Interop Assembly wrapping the legacy **SQL-DMO** COM library (SQL Distributed Management Objects) |
| `SQLDMO.DLL` | 4.5 MB | The actual SQL-DMO COM server (from SQL Server 2000 client tools era) |
| `SQLDMO.RLL` | 585 KB | SQL-DMO language resource DLL |
| `sqlsvc.dll` / `sqlsvc.rll` | 94/25 KB | SQL Server service-control helper DLLs shipped alongside SQL-DMO |
| `sqlresld.dll` | 29 KB | SQL Server resource loader helper |
| `w95scm.dll` | 49 KB | Windows 95 Service Control Manager shim (very old redistributable) |
| `ComponentFactory.Krypton.Toolkit.dll` | 2.1 MB | Krypton Free Toolkit — WinForms chrome (`KryptonForm`, `KryptonButton`, `KryptonPanel`, `KryptonComboBox`, palettes/themes) |
| `DevExpress.Data.v12.2.dll` | 3.0 MB | DevExpress 12.2 data layer |
| `DevExpress.Utils.v12.2.dll` | 3.7 MB | DevExpress utilities/skins |
| `DevExpress.XtraEditors.v12.2.dll` | 2.4 MB | DevExpress editors (incl. `RepositoryItemCheckEdit` used for hand-drawn grid checkboxes) |
| `DevExpress.XtraGrid.v12.2.dll` | 3.7 MB | DevExpress Grid (`GridControl`/`GridView` — every results grid) |
| `DevExpress.XtraLayout.v12.2.dll` | 811 KB | DevExpress layout |
| `DevExpress.Printing.v12.2.Core.dll` | 2.1 MB | DevExpress printing core (dependency of Utils) |
| `Bannar.bmp` | 101 KB | Banner bitmap resource (embedded as `Bannar` in `.resx`; sic — misspelled) |
| `SqlCompare.ico` | 22 KB | Application icon |

All third-party DLLs are dated 2016-09-25 (folder staging date); the EXE itself was rebuilt 2020-02-05.

---

## 3. Technology Stack

| Layer | Technology |
|---|---|
| Language / runtime | Visual Basic .NET (compiled to IL; `Microsoft.VisualBasic.CompilerServices` patterns, `My.*` namespace), targeting **.NET Framework 3.5** |
| UI framework | Windows Forms, skinned with **Krypton Toolkit** (`KryptonForm`, `KryptonManager` global palette) |
| Data grids | **DevExpress WinForms v12.2** `GridControl`/`GridView`, incl. `CustomDrawGroupRow` owner-draw and `RepositoryItemCheckEdit` painter reuse |
| Data access (metadata + data reads) | Classic `System.Data.SqlClient` (`SqlConnection`, `SqlCommand`, `SqlDataAdapter.Fill`) |
| Data access (scripting & execution) | **COM Interop → SQL-DMO** (`SQLServerClass`, `LoginSecure`, `Databases.Item(i)`, `Database2.Tables/StoredProcedures/UserDefinedFunctions`, `Script(SQLDMOScript_Default / SQLDMOScript_Drops)`, `ExecuteImmediate`) |
| Server/browser discovery | `SqlDataSourceEnumerator.Instance.GetDataSources()` (UDP browse) and `SqlConnection.GetSchema("Databases")` |
| Settings | Hand-rolled XML editing of its own `exe.config` `appSettings` section via `XmlDocument` |
| Target platform | Windows only (WinForms + COM). No CLI mode, no automation hooks. |

---

## 4. Application Architecture

### 4.1 Types in `SQL Compare.exe`

Decompiled namespace `SQL_Compare`:

| Type | Kind | Purpose |
|---|---|---|
| `SQLCompare` | `KryptonForm` (main) | Entire application logic: connection state, dataset caching, all 6 tabs, compare engine, sync engines, script generators, theming, progress/status plumbing. ~6,000 lines decompiled. |
| `ObjectScript` | `KryptonForm` (dialog) | Read-only rich-text viewer for a single object's script; Save → `.sql`. Holds public field `ObjName` used as default filename. |
| `ErrorForm` | `KryptonForm` (dialog) | Error report viewer: split container with RTF error log (top) and summary counters (bottom); Save → `.rtf`. |
| `CommandQuery` | Module | Seven `Const String` catalog queries (see §7). |
| `Connection` | Module | Global shared `SqlConnection NewConnction`, `StrConn`, `myTrans`, helpers `OpenConnection/CloseConnection/Ref_Trans/Save_Trans` (transactions defined but effectively unused by main flows). |
| `ManageSettings` | Class | `ReadSetting(key)` via legacy `ConfigurationSettings.AppSettings`; `WriteSetting(key,value)` rewrites the `appSettings` XML node in `Assembly.Location + ".config"`; `RemoveSetting`, `loadConfigDocument`. |
| `My.MyApplication/MyProject/MySettings/...` | VB plumbing | Standard `My` namespace shims, `WinForms_RecursiveFormCreate` unhandled-exception guard. |
| `Resources` | `.resx` | Embedded images: `Bannar`, `Compare`, `ExitForm`, `Expand`, `collapse`, `RunScript`, `SaveFile`, `SaveFile_32x32`, `checkbox_no`, `checkbox_yes`. |

### 4.2 Enumerations (on main form)

```vb
Enum ConnectionToServer : Server1 = 0 : Server2 = 1
Enum ColumnTypes       : TextBox = 0 : CheckBox = 1
```

### 4.3 Key fields on `SQLCompare`

- Connection state: `Server1/Server2`, `DB1/DB2`, `UserName1/UserName2`, `Password1/Password2`, `ConnType1/ConnType2 As Boolean` (False = Windows auth, True = SQL auth).
- Cache: single `DataSet Ds` holding named `DataTable`s:
  `DB1Objects, DB2Objects, DB1DiffObjects, DB2DiffObjects, DB1Columns, DB2Columns, DB1DiffColumns, DB2DiffColumns, DB1PKs, DB2PKs, DB1DiffPKs, DB2DiffPKs, DB1FKs, DB2FKs, DB1DiffFKs, DB2DiffFKs, DBSpsAndObject1/2, DBCopy1/2`.
- Owner-draw state: `CheckedRows As Hashtable` (group-row checkbox states), `EditorRects As Hashtable` (hit-test rectangles), `FilterDt As DataTable` (preserves each grid's `ActiveFilterString` across refreshes).
- Progress counters: `ProgRows As Long`, `i As Integer`, `VIndex`.

### 4.4 `SQLDetection.dll` (connection picker control)

A `UserControl` exposing properties consumed by the main form:

```vb
Public Enum PropertiesEnum : WindowsMode = 0 : SQLMode = 1
Property ServerName As String        ' cmbServer.Text
Property DataBaseName As String      ' cmbDB.Text
Property AuthenticationType As PropertiesEnum
Property UserName As String
Property Password As String
Sub LoadServers()
Sub LoadDataBase()
```

Behaviour:
- **Refresh servers** button → `SqlDataSourceEnumerator.Instance.GetDataSources()`; items rendered as `ServerName[\InstanceName]`.
- **Auth radios**: Windows mode enables DB picker immediately; SQL mode disables DB picker until a username is typed.
- **Refresh/dropdown databases** → opens `SqlConnection` with `Integrated Security=True` or `User ID=…; Password=…`, calls `conn.GetSchema("Databases")`, binds `Database_Name` to the combo.
- Two instances are placed on the main form top strip: `SqlDetection1` (left, source) and `SqlDetection2` (right, target).

### 4.5 Call graph (simplified)

```
btnCompare_Click
 ├─ ManageSettings.WriteSetting ×10          (persist current pickers to exe.config)
 └─ SQLCompare()                              (the compare engine; note: same name as class)
     ├─ GetFilter(TabControl1)                (snapshot grid filters)
     ├─ Active_Deactive_Buttons(false)
     ├─ GetConnectionSetting()                (SqlDetection* → private fields)
     ├─ validation: two servers? two databases?
     ├─ Clear()
     ├─ CompareObjects()      → GetObjectInfromation(Server1|2,"DBxObjects") + set diff
     ├─ CompareColumns()      → GetColumnInformation(...)     + set diff
     ├─ ComparePrimaryKeys()  → GetPKInformation(...)         + set diff
     ├─ CompareForeignKeys()  → GetFKInformation(...)         + set diff
     ├─ LoadGridDB / LoadGridColumn / LoadGridPK / LoadGridFK   (bind grids)
     ├─ LoadAllSPsAndFunctions(...,"DBSpsAndObject1")
     ├─ LoadTablesToCopy(...,"DBCopy1")
     └─ SetFilter(TabControl1); Active_Deactive_Buttons(true)

btnRunObjScript_Click / btnRunScriptAllSPsFun_Click
 └─ Synchronization(grid, conn params ×2, checkedCount)
     ├─ SQLServerClass ×2 (connect both)
     ├─ per checked row: build script (DMO Script() / GetUserDefineTableTypeScript)
     │    └─ targetDb.ExecuteImmediate(command)
     ├─ collect failures → ErrorForm
     └─ re-run SQLCompare()

btnRunScriptColumns_Click → RunColumnsScript()  (ALTER TABLE generator, §8.3)
btnRunScriptCopyData_Click → CopyData(...)      (row-by-row copy, §8.6)
btnSaveObjScript_Click / btnSaveScriptAllSPsFun_Click → SaveScript(...) → .sql
btnSaveScriptCol_Click → SaveColumnScript(n)
btnSaveScriptCopyData_Click → SaveCopyDataScript(...)
GridView double-click → GetScript(one object) → ObjectScript.ShowDialog()
```

---

## 5. User Interface Walkthrough

**Window title:** `SQL Compare`. Single resizable Krypton form.

### Top strip
- `SqlDetection1` (left, 392×235): source connection.
- `SqlDetection2` (right): target connection.
- Divider labels (`______`), theme combo `CboThemes` with 5 entries:
  `"Office 2007 - Silver", "Office 2007 - Blue", "Sparkle - Blue", "Sparkle - Orange", "Sparkle - Purple"` → maps to Krypton `PaletteModeManager.Office2007Silver/Office2007Blue/SparkleBlue/SparkleOrange/SparklePurple`; choice persisted to config key `Theme`.
- Status label (`lblStatus`, starts "Ready"), `ProgressBar1` (swaps visibility with the combo during work), big **Compare** button.

### Scope checkboxes (with coupling rules)
| Control | Meaning | Coupling logic |
|---|---|---|
| `ChkObj` — Compare Objects | include object-level diff | Unchecking it force-unchecks Col/PK/FK |
| `ChkCol` — Compare Columns | include column diff | Checking it force-checks Objects |
| `ChkPK` — Compare PKs | include primary keys | Checking force-checks Objects |
| `ChkFK` — Compare FKs | include foreign keys | Checking force-checks Objects |

### Tabs (order as coded; note the designer numbering)

| # | Caption | Contents | Buttons |
|---|---|---|---|
| TabPage1 | `(1) Compare Objects` | Left grid = objects present in DB1 but absent in DB2 (checkable rows); right grid = mirror (objects in DB2 absent in DB1, no checkbox). Columns: Object Name, Object Type, ✔. Rows tinted salmon when checked; Space toggles check; row click toggles check; double-click opens the object's script viewer. | Select All / Unselect All · **Run Script** · **Save Script** |
| TabPage2 | `(2) Compare Columns` | Both sides grouped by table name. Columns: Table Name (group), Column Name, Type, Length, ✔ (custom-drawn on group rows), **Value** (free-text default value for backfill). | Select/Unselect All · Expand/Collapse All ×2 · Run Script · Save Script |
| TabPage5 | `(3) Compare PKs` | Grouped by table: Column, Type Name, Length. Read-only diff display. | Expand/Collapse All ×2 |
| TabPage6 | `(4) Compare FKs` | Columns: Relation Name (group), PK Table, Column, FK Table, Column. | Expand/Collapse All ×2 |
| TabPage3 | `(5) All SP's And Fun's` | Complete list of stored procedures + scalar/inline/multi-statement functions from each DB (checkable on DB1 side). | Select/Unselect All · Run Script · Save Script |
| TabPage4 | `(6) Copy Data` | Tables from DB1 whose names match `%menu%|%Programs|%Messag|%Massag|%Page%` (the ERP's menu/program/message/page configuration tables), checkable. | Select/Unselect All · **Run Script** (copy data now) · **Save Script** (emit merge `.sql`) |

UX details reverse-engineered from handlers:
- `Gv_KeyDown`: Space toggles the hidden `Chk` cell (`NotObject` flip).
- `Gv_RowStyle`: checked rows get gradient `Color.Salmon → Color.SeaShell`.
- `Gv_RowClick`: clicking anywhere in the row flips its checkbox (fast triage UX).
- On load the code cycles `TabControl.SelectedIndex` 5→4→3→2→1→0 to force all tab pages to instantiate (paint warm-up).
- During long operations every `KryptonButton` under `TabControl1` plus the compare button, both detection panels and the four scope checkboxes are disabled recursively (`Active_Deactive_Buttons`).
- `GetFilter/SetFilter` preserve each `GridView.ActiveFilterString` in `FilterDt` so user-applied grid filters survive a re-compare.

---

## 6. Configuration System

`SQL Compare.exe.config` — two sections:

1. `system.diagnostics` — stock VB `FileLogTraceListener` template (unused noise from the project template).
2. `appSettings` — the actual persisted state:

| Key | Shipped value | Meaning |
|---|---|---|
| `Server1` | `10.0.10.105` | Source (reference) server |
| `DataBase1` | `Olives_Images` | Source database |
| `ConnType1` | `1` | 1 = SQL authentication, 0 = Windows authentication |
| `UserName1` | `cds` | SQL login |
| `Password1` | `cdc2014cdc` | **Plaintext password** |
| `Server2` | `.` | Target server (local default instance) |
| `DataBase2` | `Olives_Images_AlMalak` | Target database (customer fork) |
| `ConnType2` | `0` | Windows auth |
| `UserName2` / `Password2` | *(empty)* | — |
| `Theme` | `Office2007Silver` | Krypton palette |

Persistence flow: loaded in `SQLCompare_Load` into the two `SqlDetection` widgets; written back by `btnCompare_Click` **after every successful compare** via `ManageSettings.WriteSetting` (which removes/re-adds `<add>` nodes with raw `XmlDocument` XPath — note the XPath `//add[@key='{key}']` is injectable if a key ever contained `'`, keys are hardcoded so not exploitable).

---

## 7. Database Metadata Queries (the core SQL)

Everything relies on **backward-compatibility catalog views** (SQL Server 2000 style) plus a few 2005+/2008+ catalog views for table types. Exact strings (constants in `CommandQuery`, duplicated inline in fetchers):

### 7.1 Full object inventory (`GetObjectInfromation` → `DBxObjects`)
```sql
SELECT name, id, xtype, uid,
  case when xtype='U' then 'Table' else case when xtype='P' then 'Stored Procedure'
    else 'Function' end end as TypeName,
  CASE WHEN xtype='U' THEN 1 ELSE CASE WHEN xtype='FN' THEN 3 ELSE CASE WHEN xtype='IF' THEN 4
    ELSE CASE WHEN xtype='TF' THEN 5 ELSE CASE WHEN xtype='P' THEN 6 END END END END END AS SortID
FROM dbo.sysobjects WHERE (xtype IN ('IF','TF','FN','P','U'))
UNION
SELECT tt.name, tt.type_table_object_id as id, 'TT' as xtype, ii.uid,
  'User Define Table Type' AS TypeName, 2 AS SortID
FROM sys.table_types tt INNER JOIN dbo.sysobjects ii ON tt.type_table_object_id = ii.id
WHERE is_table_type='1'
ORDER BY SortID, name
```
Sort priority: Tables(1) → UDTTs(2) → scalar FN(3) → inline IF(4) → multistatement TF(5) → procs(6). Primary key for set ops: `(name, uid)`.

### 7.2 Column inventory (`GetColumnInformation` → `DBxColumns`)
Joins `sysobjects → syscolumns → systypes` for `xtype='U'` tables; computes a display `length`:
- `nvarchar/nchar` → bytes/2 (char count),
- `sql_variant` → `''`,
- `numeric` → `"prec,scale"`,
- else raw byte length.
Primary key: `(name, uid, ColumnName, TypeName, length)` — this is what makes a type-or-length change register as a "modified" column.

### 7.3 Primary keys (`GetPKInformation` → `DBxPKs`)
`sysindexes ⋈ sysobjects ⋈ sysfilegroups ⋈ sysindexkeys ⋈ syscolumns ⋈ systypes ⋈ INFORMATION_SCHEMA.TABLE_CONSTRAINTS` filtered `CONSTRAINT_TYPE='PRIMARY KEY'`, `xtype='U'`; returns index id/name, key column, type, length. PK of result: `(name, uid, ColName)`.

### 7.4 Foreign keys (`GetFKInformation` → `DBxFKs`)
`sysforeignkeys ⋈ sysobjects ×3 ⋈ syscolumns ×2`; returns `FKTab, PKTab, RelName (constraint name), ColName (FK col), ColName2 (referenced col)`. PK of result: `(RelName, FKTab, uid, ColName, PKTab)`.

### 7.5 All procedures/functions list (`GetDBSPsAndFunctions` → `DBSpsAndObject1/2`)
```sql
SELECT Cast(0 AS Bit) AS Chk, name, id, xtype, uid, …
FROM dbo.sysobjects WHERE (xtype IN ('IF','TF','FN','P')) ORDER BY TypeName, name
```

### 7.6 Tables eligible for Copy Data (`GetTables` → `DBCopy1/2`)
```sql
SELECT Cast(0 AS Bit) AS Chk, name, id, xtype, uid, …
FROM dbo.sysobjects
WHERE (xtype IN ('U'))
  AND (name LIKE N'%menu%' OR name LIKE N'%Programs%' OR name LIKE N'%Messag%'
       OR name LIKE N'%Massag%' OR name LIKE N'%Page%')
ORDER BY name
```
(The `%Messag%`/`%Massag%` double-spelling covers both naming conventions found in the Olives schema.)

### 7.7 User-defined table type columns (`GetUserDefineTableTypeScript`)
```sql
SELECT tt.name AS table_type_name, c.name AS column_name, c.column_id, t.name AS type_name,
  CASE WHEN t.name='nvarchar' THEN c.max_length/2 ELSE c.max_length END AS max_length,
  c.precision, c.scale, c.collation_name, c.is_nullable
FROM sys.columns c
JOIN sys.table_types tt ON c.object_id = tt.type_table_object_id
JOIN sys.types t ON t.user_type_id = c.user_type_id
WHERE tt.name = '{ObjectName}'
ORDER BY table_type_name, c.column_id
```

### 7.8 Clustered-index key lookup (used by Copy Data fallback & merge-script mode)
```sql
SELECT dbo.syscolumns.name AS ColName
FROM dbo.sysobjects JOIN dbo.syscolumns ON …
JOIN dbo.sysindexkeys ON syscolumns.id=… AND syscolumns.colid=…
WHERE (dbo.sysobjects.name = N'{table}') AND (dbo.sysindexkeys.indid = 1)
```
i.e., "columns of index id 1" ≈ clustered index ≈ usually the PK.

> **Compatibility note:** all of these work on any SQL Server ≥ 2000 (compat views survive to current versions), but the UDTT branch requires ≥ 2008, and the execution layer (SQL-DMO, §9) realistically caps support at **SQL Server 2008 R2**.

---

## 8. Feature Deep-Dives

### 8.1 The Compare Workflow (`btnCompare_Click` → `SQLCompare()`)

1. Persist both picker configurations to `exe.config`.
2. Snapshot grid filters; disable all controls.
3. `GetConnectionSetting()` copies picker values into private fields; map `AuthenticationType` → `ConnType bool`.
4. Validation: *"You must select two server"* / *"You must select two Databases"* message boxes.
5. `Clear()` resets the DataSet, all 12 grids, checkbox hash tables, button images.
6. For each enabled scope: fetch both catalogs into `Ds` (any failure → `"Error in table Objects1"`-style box and abort of that section).
7. **Set-difference loops** (`foreach` + `Rows.Find`):
   - Objects: every row of `DB1Objects` not found in `DB2Objects` (by `(name,uid)`) lands in `DB1DiffObjects`; vice-versa for `DB2DiffObjects`.
   - Columns: only rows whose parent table is *not already* in the corresponding `DBxDiffObjects` are compared (avoids duplicate noise); missing `(name,uid,ColumnName,TypeName,length)` → diff row; `length <= 0` rendered as `"MAX"`.
   - PKs/FKs: same pattern, skipping tables already flagged at object level.
   - Progress bar advances per row (`i / ProgRows * 100`).
8. Bind diff tables to grids with tailored column sets (`LoadGridDB/LoadGridColumn/LoadGridPK/LoadGridFK` — every grid gets `BestFitColumns`, column moving/menu disabled).
9. Always load Tab 5 (all SPs/funs) and Tab 6 (copy-data table list) from DB1 regardless of scope checkboxes.
10. Restore filters, re-enable UI, jump to tab 0 (or tab 4 when object-compare unchecked).

> **Semantic limitation (important):** this is a *presence/type-shape* differ. It does **not** compare procedure/function bodies, index composition beyond PK columns, triggers, views, defaults, checks, users, or extended properties. An SP changed on one side will never appear as a difference — operators use Tab 5 to eyeball/script specific routines manually.

### 8.2 Object Synchronization — "Run Script" (`Synchronization`)

For every checked row of the active grid (objects tab or SPs/funs tab):

1. Connect to **both** servers with SQL-DMO (`LoginSecure=True` + `Connect(server,…)` for Windows auth, else `Connect(server,user,pwd)`).
2. Locate the source/target database by linear scan of the 1-based COM collections (case-insensitive name match).
3. Build the command per object type:
   - **Table** → `Table.Script(SQLDMOScript_Default)` (full CREATE TABLE incl. constraints/indexes as DMO emits them), post-processed by `FixScript` (§8.3).
   - **Stored Procedure / Function** → `Script(SQLDMOScript_Drops)` + CRLF + `Script(SQLDMOScript_Default)` → classic *drop-and-recreate* pair.
   - **User Define Table Type** → hand-built `CREATE TYPE [dbo].[X] AS TABLE (...)` from the §7.7 metadata (per-type length formatting, `precision,scale` for decimal, trailing `NULL`/`NOT NULL`, closing `)\r\nGO\r\n\r\n\r\n\r\n`), also passed through `FixScript`.
4. Execute on the **target** DB: `targetDb.ExecuteImmediate(cmd, SQLDMOExec_Default)`.
5. Error handling per object:
   - If `Err().Description = "This server has been disconnected.  You must reconnect to perform this operation."` → message box, abort loop.
   - Otherwise append `"TypeName - name"` + exception text to an in-memory `RichTextBox`; increment per-type counters (tables / SPs / functions / UDTTs).
6. After the loop: disconnect both servers, **automatically re-run the whole compare** so grids show the new state.
7. If any errors occurred, open `ErrorForm` with the RTF log (object headers re-formatted bold-italic 9pt) and a summary pane:
   `Number Of Total Errors / Tables Errors / Stored Procedures Errors / Functions Errors / User Define Table Type Errors`.

### 8.3 Column Diff Sync (`RunColumnsScript` and `SaveColumnScript`)

Selection model: group-row checkboxes (owner-drawn) set a `Selected` flag on every row of that table inside `DB1DiffColumns`; per-row `Value` supplies an optional backfill constant; per-row `Chk` marks "this new column should receive the value".

Generated SQL matrix (source DB collation fetched via SQL-DMO `database.Collation`):

| Type family | ADD (new col) | ALTER COLUMN (fix existing) | Backfill UPDATE (if Chk+Value) |
|---|---|---|---|
| bigint/bit/datetime/float/image/int/money/real/smalldatetime/smallint/smallmoney/sql_variant/timestamp/tinyint/uniqueidentifier | `ALTER TABLE [T] ADD [C] TYPE NULL` | `ALTER TABLE [T] ALTER COLUMN [C] TYPE` | numeric-ish → `SET C = value` (unquoted); datetime → quoted |
| text / ntext | `ADD [C] TYPE COLLATE <dbcollation> NULL` | `ALTER COLUMN … COLLATE …` | none |
| binary / varbinary(n) | `ADD [C] TYPE(len) NULL` | `ALTER COLUMN TYPE(len)` | none |
| char/nchar/varchar/nvarchar(n) | `ADD [C] TYPE(len) COLLATE <dbcollation> NULL` | `ALTER COLUMN … COLLATE …` | `SET C = 'value'` |
| decimal / numeric(p,s) | `ADD [C] TYPE(p,s) NULL` | `ALTER COLUMN TYPE(p,s)` | `SET C = value` |

Execution order per column (live-run mode): try `ADD`, then try `UPDATE` backfill, then separately try `ALTER COLUMN` — **each wrapped in silent try/catch** (failures invisible!). `-1`/`0` lengths normalized to `Max`. Afterwards: disconnects, re-runs full compare, auto-clicks `ChkSelectAllColumns` to reset selection state.

`FixScript` post-processing (applies to DMO output which renders `MAX` types as length 0):
```
[nvarchar] (0) → [nvarchar] (MAX)
[varchar]  (0) → [varchar]  (MAX)
varbinary(0)   → varbinary(MAX)
```

### 8.4 Compare PKs / FKs (tabs 3 & 4)

Purely **reporting**: the diff tables from §7.3/§7.4 are displayed grouped, expandable, filterable. There are no "Run Script" buttons — PK/FK changes reach the target indirectly because DMO's `CREATE TABLE` script includes PKs, and the operator scripts FK-bearing tables manually from tab 1.

### 8.5 All SPs & Functions (tab 5)

Loads the complete routine list of each DB (`§7.5`). Double-click → script preview. Checked rows behave exactly like tab 1 (same `Synchronization` engine), enabling e.g. "push these 30 procedures to the customer DB".

### 8.6 Copy Data Engine (`CopyData` — tab 6 "Run Script")

Per checked table `T`:

1. Script target-side rebuild: `T.Script(SQLDMOScript_Drops)` + `T.Script(SQLDMOScript_Default)` executed on DB2. If that throws (e.g., dependent FK), remember `flag=true`.
2. Pull full contents: `SELECT * FROM T` via SqlDataAdapter into a DataTable (source connection from `Connection.NewConnction`).
3. **Row-by-row INSERT generation** (string concatenation):
   - Skips identity columns (`DataColumn.AutoIncrement`).
   - Value rendering: `DBNull → NULL`; `String → 'value'`; `Boolean → 1/0`; others raw.
   - ⚠️ Sanitization is destructive: `value.Replace("'", "")` — apostrophes are **deleted**, silently corrupting text like `Al'Malak` → `AlMalak`.
   - Executes each INSERT immediately via SQL-DMO; exceptions swallowed.
4. Fallback when the drop/create failed (`flag=true`): builds `Update T SET col=val, … WHERE (k1=v1)(k2=v2)…` per row, where key columns = clustered-index columns from §7.8, executed as one batch.
5. Re-compare, restore UI.

### 8.7 Merge Script Generator (`SaveCopyDataScript` — tab 6 "Save Script")

Writes a portable `.sql` file (VB6-style `FileSystem.FileOpen/Print`) containing per table:
1. `DELETE FROM T` + `GO`;
2. per row an **idempotent upsert preamble**: `SELECT * FROM T WHERE (key = val)…` + `GO`-separated `IF @@ROWCOUNT = 0 BEGIN INSERT INTO T (cols) VALUES (vals) END` (when target key info available), else plain `INSERT`;
3. additionally per row an `UPDATE T SET … WHERE (keys)` block.

Same quote-stripping flaw applies. This artifact can be handed to customers to replay reference data without the tool.

### 8.8 `ObjectScript` viewer

Double-clicking any object row (either side) resolves its DMO script (single-object variant of §8.2 logic, incl. the manual UDTT builder) into a read-only `KryptonRichTextBox`; Save defaults filename to `ObjName`, filter `(*.sql) SQL File | *.sql`, saves as plain text (`RichTextBoxStreamType` 4 = TextTextOleTexts → textual).

### 8.9 `ErrorForm`

Two-pane splitter: top = colored RTF log; bottom = counters (see §8.2.7). Save → WordPad `.rtf`. Close button doubles as `CancelButton` (Esc).

---

## 9. The SQL-DMO Legacy Layer

Why COM? In 2010 (tool origin) **SMO** existed, but SQL-DMO was simpler for drop-in "give me the CREATE script / execute this batch" semantics. Consequences visible in the code:

- Every collection access is late-bound/1-based: `Databases.Item(i, Missing.Value)`; the code linear-searches by name then does `Cast<object>().ElementAtOrDefault(i-1)` — an awkward hybrid that throws NRE if the DB vanished mid-session (loop exits with `i = count+1`, `ElementAtOrDefault(count)` → null).
- `ExecuteImmediate` runs arbitrary batches — GO-separated scripts are fine.
- `SQLDMOScript_Drops | Default` combos produce `DROP … / CREATE …` pairs; there is no idempotency (`IF EXISTS` guards) except what DMO emitted circa SQL 2000.
- SQL-DMO was **deprecated in SQL 2005 and removed from client installers after SQL 2008 R2**; on modern machines you must install the *SQL Server 2005 Backward Compatibility Components* (or copy the shipped `SQLDMO.DLL` + register via `regsvr32`) for this EXE to start at all.
- All scripting/executing happens on the UI thread with `Application.DoEvents()` pumping — long syncs freeze/redraw the window but keep the progress bar alive.

---

## 10. Connection Handling

- Metadata/data reads: fresh `SqlConnection` per operation from `GetConnectionString(Server)`:
  - Windows: `Data Source={S};Initial Catalog={D};Integrated Security=True`
  - SQL: `Data Source={S};initial catalog={D}; User ID={U}; Password={P};Connect Timeout = 120`
- The `Connection` module holds one global connection + transaction helpers (`Ref_Trans`, `Save_Trans`) — vestigial; the main flows open/close ad hoc.
- No pooling tweaks, no encryption flags, no retry logic. Disconnects mid-sync surface as the special-cased DMO error string.

---

## 11. Themes & Branding

- Five Krypton palettes selectable at runtime; both Krypton chrome *and* the DevExpress `DefaultLookAndFeel` skin are switched together (Office2007Blue ↔ "Office 2010 Blue" DevExpress skin; everything else ↔ "DevExpress Style").
- Choice written to `Theme` appSetting; startup restores it (default Office2007Silver).
- Embedded `Bannar.bmp` banner and `Compare/Expand/collapse/RunScript/SaveFile/SaveFile_32x32/checkbox_yes/checkbox_no/ExitForm` icons drive the toolbar-style buttons.

---

## 12. Security Findings

| Severity | Finding | Evidence |
|---|---|---|
| High | **Plaintext credentials on disk** — SQL login `cds` / password `cdc2014cdc` for `10.0.10.105` committed inside the repo folder (`exe.config`), rewritten on every compare | `appSettings` block |
| High | **SQL injection surface** — the user-editable `Value` grid column is interpolated verbatim into `UPDATE {table} SET {col} = {value}`; identifiers interpolated unquoted-escaped from catalog values | `RunColumnsScript`, `SaveColumnScript` |
| Medium | **Quote stripping instead of escaping** — `Replace("'", "")` on all copied string data corrupts legitimate content and is not injection-safe either | `CopyData`, `SaveCopyDataScript` |
| Medium | Requires elevated DB rights: direct reads of system catalogs + DDL exec via DMO | throughout |
| Low | Config rewrite uses string-built XPath (keys hardcoded ⇒ not exploitable today) | `ManageSettings.WriteSetting` |
| Low | No TLS enforcement, `Connect Timeout=120`, no credential prompts (password lives only in config) | `GetConnectionString` |

---

## 13. Defects & Quirks Found in Code

1. **Multi-column key loss in WHERE builders** (`CopyData` fallback, `SaveCopyDataScript`): the separator logic
   ```vb
   If text7 <> "" Then text7 = " AND "
   text7 &= $"({col} = "
   ```
   **overwrites** previously accumulated predicates, so composite clustered keys degrade to `WHERE (last_key_col = …)` — potentially mass-updating rows that share only the final key component.
2. **Silent exception swallowing** in column sync and per-row copy (`catch … ClearProjectError()` with no logging) — failed ALTERs vanish without trace; only the object-sync path surfaces an ErrorForm.
3. Inconsistent MAX normalization: live column run treats `length == "-1"` as Max; the save-script twin treats `"0"` as Max.
4. Off-by-one hazard in DMO lookups (`ElementAtOrDefault(i-1)` after a failed name search) → NRE surfaced as a generic MsgBox.
5. `GetFilter` walks children twice (outer loop already descends, inner loop re-descends siblings) — harmless duplication.
6. Empty `KryptonButton1_Click` stub; duplicated `ProgressSetting("Ready"…)` call in `btnExpAllPK2_Click`.
7. Designer label texts `Label9/Label10` both say "Columns In Database 1 Not In Database 2" even on the DB2 grid (cosmetic copy-paste bug).
8. `ObjectScript`/`ErrorForm` define finalizers calling `Finalize()` — redundant VB.NET relic.
9. Identity columns excluded from INSERTs means target-side identity seeds may diverge after copy (`DBCC CHECKIDENT` never issued).
10. The tool assumes `dbo` schema everywhere (queries hardcode `dbo.sysobjects`, scripts emit `[dbo].[]` for types only).

---

## 14. Runtime Requirements & How To Run It Today

To execute the original binary you need **Windows** with:

1. .NET Framework 3.5 feature enabled (works on Win 10/11 after enabling *".NET Framework 3.5"* in Optional Features).
2. SQL-DMO available: install **Microsoft SQL Server 2005 Backward Compatibility Components** (contains `SQLDMO.DLL`), or `regsvr32` the `SQLDMO.DLL` shipped next to the EXE. Without it the process fails at first `new SQLServerClass()`.
3. DevExpress 12.2 + Krypton assemblies — already side-by-side in the folder.
4. A reachable SQL Server ≤ 2008 R2 for the *execution* features (DMO), although metadata reading works against newer servers via SqlClient.

It **cannot run on this Linux workstation** (WinForms + 32-bit COM). The analysis above was produced purely by static decompilation. Practical modern alternatives: run it in a Windows VM/Winetricks-with-.NET sandbox, or replace it (§16).

---

## 15. Relationship to the Olives Repository

- Location `apps/drift-tool/` groups it as the schema-drift management utility among internal Olives tools (desktop launchers exist: `drift-tool.desktop`, `Olives Drift Tool.desktop`).
- The configured pair `Olives_Images` (HQ server `10.0.10.105`) ⇄ `Olives_Images_AlMalak` matches the repo-wide pattern of customer-specific forks of the Olives imaging/product database (cf. Obsidian vault notes on `Olives_BO`; same ecosystem, different DB).
- Its Copy Data whitelist (`menu / Programs / Messag(e) / Page`) targets exactly the ERP's runtime-config tables that differ per deployment — i.e., the tool's day job is "pull latest menus/pages/messages from HQ into a customer DB, and push structural drift the other way".
- Credentials embedded here correspond to the shared `cds` support login referenced across Olives support documentation — rotate if rotating that account.

---

## 16. Modern Rewrite Guidance

If replacing rather than preserving, a faithful-but-safe port would be:

- **Engine:** Microsoft.SqlServer.Management.Smo (SMO) — `Server.ConnectionContext`, `db.Tables[schema,name].Script()`, `Transfer` class, or `SqlPackage/DacFx` for full-fidelity diff+publish.
- **Diff:** query `sys.tables/sys.procedures/sys.columns/key_constraints/foreign_keys` + `OBJECT_DEFINITION()` to also catch body changes (the one capability this tool lacks).
- **Execution:** parameterized DDL via `SqlConnection.ExecuteNonQuery` with `SqlCmd` batching, transactional scopes, and `IF NOT EXISTS` guards.
- **UI parity:** WinForms/WPF with DataGridView, or a CLI (`dotnet tool`) + CI job — the current tool's whole flow is automatable.
- **Config:** store secrets in DPAPI/user-secrets, never in the repo.
- **Fixes to carry over knowingly:** keep the `MAX` normalization, keep per-type column SQL matrix (§8.3), replace quote-stripping with proper escaping (`''` doubling), fix the composite-key WHERE bug.

---

## 17. Reverse Engineering Methodology Used

1. **Inventory:** `ls`/`file` classification — identified a .NET GUI EXE plus COM interop chain and vendor UI DLLs.
2. **Surface strings:** `strings -el` on the EXE exposed all embedded SQL constants, UI captions, config keys, and version resources before any decompilation.
3. **Decompilation:** ILSpy 8.2 (`ilspycmd -p`) produced a full compilable-shaped C# projection of the VB.NET assembly (6,036-line main form) plus the 40 KB `SQLDetection.dll`.
4. **Cross-checks:** `exe.config` matched the `ManageSettings` reader/writer logic; resource names matched `.resx`; DevExpress/Krypton APIs matched the grid setup code.
5. **Behavior reconstruction:** event-handler-by-event-handler trace (§4.5 call graph), yielding the algorithms, defect list, and security findings above. Nothing was executed against live databases.

*End of report.*
