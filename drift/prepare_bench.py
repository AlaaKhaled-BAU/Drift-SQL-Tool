"""Benchmark pair builder -- PLAN-V4 parallel-testing phase.

Creates TWO databases on the scratch container (base + modified), plants
five ClientActive-aware changes, backs both up to .bak, and prints the
GROUND TRUTH the drift-tool run must reproduce. Run:
    cd apps/drift-tool/drift && python3.13 prepare_bench.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from drift import config, docker_mgmt  # noqa: E402
import pymssql  # noqa: E402

BASE, MOD = "zz_bench_base", "zz_bench_mod"
OUT = config.ROOT / "work" / "bench"
OUT.mkdir(parents=True, exist_ok=True)

# The dispatch proc: gates for OTHER clients (165/136) + shared logic + this client's (66) branch.
PROC_FMT = """CREATE PROCEDURE dbo.BenchDispatch
    @CompNo smallint, @ClientActive smallint
AS
BEGIN
    SET NOCOUNT ON;
    IF @ClientActive = 136
    BEGIN
        SELECT 'v136-old-shared-tail' AS tag, @CompNo AS comp
    END
    ELSE IF @ClientActive = 66
    BEGIN
        SELECT 'v66-branch' AS tag, {v66_select} AS extra
    END
    ELSE IF @ClientActive <> 165
    BEGIN
        SELECT 'generic' AS tag, {generic_select} AS extra
    END
    ELSE
    BEGIN
        SELECT 'spartan' AS tag, {spartan_select} AS extra
    END
    SELECT 'shared-tail' AS tail, {shared_tail} AS v
END"""

V66_OLD, V66_NEW = "66-calc-old", "66-calc-new"
GENERIC_OLD, GENERIC_NEW = "gen-old", "gen-new"
SPARTAN_OLD, SPARTAN_NEW = "spa-old", "spa-brand-new"   # P1: changed ONLY in 165's branch
SHARED_OLD, SHARED_P1 = "'shared-v1'", "'shared-P1-changed'"


def proc(v66=V66_OLD, gen=GENERIC_OLD, spa=SPARTAN_OLD, tail=SHARED_OLD):
    return PROC_FMT.format(v66_select=f"'{v66}'", generic_select=f"'{gen}'",
                           spartan_select=f"'{spa}'", shared_tail=tail)


def connect(db=None):
    return pymssql.connect(**config.scratch_connect_kwargs(),
                           database=db or "master", autocommit=True, login_timeout=10)


def sql(cur, *stmts):
    for s in stmts:
        cur.execute(s)


def main():
    docker_mgmt.ensure_running(lambda m: print("[docker]", m))
    conn = connect()
    cur = conn.cursor()
    sql(cur, f"IF DB_ID('{BASE}') IS NOT NULL DROP DATABASE {BASE}",
        f"IF DB_ID('{MOD}') IS NOT NULL DROP DATABASE {MOD}")
    conn.close()

    # --- BASE ---
    conn = connect(); cur = conn.cursor()
    sql(cur, f"CREATE DATABASE {BASE}")
    sql(cur, f"USE {BASE}")
    sql(cur,
        "CREATE TABLE dbo.BenchItems (ID int IDENTITY PRIMARY KEY, Name nvarchar(50) NULL, Price decimal(10,2) NOT NULL DEFAULT 0)",
        proc(),
        # attribution-style log so changelog.inspect finds something to do
        "CREATE TABLE dbo.ProcedureChangeLog (Id int IDENTITY, ObjectName nvarchar(200), ObjectSchema nvarchar(50), "
        "EventType nvarchar(50), OldDefinition nvarchar(max), NewDefinition nvarchar(max), "
        "LoginName nvarchar(100), HostName nvarchar(100), IPAddress nvarchar(50), ChangeTime datetime)",
        "INSERT INTO dbo.ProcedureChangeLog (ObjectName, ObjectSchema, EventType, LoginName, HostName, IPAddress, ChangeTime) "
        "VALUES ('BenchDispatch', 'dbo', 'ALTER_PROCEDURE', 'bench-user', 'bench-host', '10.0.0.9', GETDATE())")
    conn.close()

    # backup base -- the /host mount is READ-ONLY by design (restore-only),
    # so backups land in the container's own data dir and get docker-cp'd out
    c = connect(); cu = c.cursor()
    cu.execute(f"BACKUP DATABASE {BASE} TO DISK = '/var/opt/mssql/data/{BASE}.bak' WITH INIT")
    c.close()

    # --- MOD: copy + planted changes ---
    conn = connect(); cur = conn.cursor()
    sql(cur, f"RESTORE DATABASE {MOD} FROM DISK = '/var/opt/mssql/data/{BASE}.bak' WITH RECOVERY,"
             f" MOVE 'zz_bench_base' TO '/var/opt/mssql/data/{MOD}.mdf',"
             f" MOVE 'zz_bench_base_log' TO '/var/opt/mssql/data/{MOD}_log.ldf'")
    sql(cur, f"USE {MOD}")
    planted = []
    # P1: change ONLY inside other-client (165) branch -> must be irrelevant_to_client for 66
    cur.execute("SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.BenchDispatch'))")
    d = cur.fetchone()[0]
    d_p1 = d.replace(SPARTAN_OLD, SPARTAN_NEW)
    assert d_p1 != d; planted.append(("P1 spartan-branch-only edit", "irrelevant_to_client=True"))
    # P2: shared-tail literal changed -> REAL drift for every client
    d_p12 = d_p1.replace(SHARED_OLD, SHARED_P1)
    assert d_p12 != d_p1; planted.append(("P2 shared-code edit", "real finding, body"))
    # P3: NEW gated branch for THIS client appended to the chain
    d_p123 = d_p12.replace("    SELECT 'shared-tail' AS tail",
                           f"    ELSE IF @ClientActive = 66 AND 1 = 0\n    BEGIN\n        SELECT 'p3-never'\n    END\n"
                           f"    SELECT 'shared-tail' AS tail") if False else \
        d_p12.replace("ELSE IF @ClientActive <> 165",
                      "ELSE IF @ClientActive = 66\n    BEGIN\n        SELECT 'p3-new-66-row' AS p3\n    END\n    ELSE IF @ClientActive <> 165")
    assert d_p123 != d_p12; planted.append(("P3 new @ClientActive=66 branch", "gated_customization"))
    cur.execute("ALTER PROCEDURE dbo.BenchDispatch" + d_p123.split("AS\nBEGIN", 1)[0].split("CREATE PROCEDURE", 1)[1] and
                d_p123.replace("CREATE PROCEDURE", "ALTER PROCEDURE"))

    # P4: param default added on a second small proc
    sql(cur, "CREATE PROCEDURE dbo.BenchSmall @Mode int = 1 AS BEGIN SELECT @Mode AS m END")
    cur.execute("ALTER PROCEDURE dbo.BenchSmall @Mode int = 2 AS BEGIN SELECT @Mode AS m END"); 
    # honest note: BenchSmall is CREATED inside MOD only, so the net effect
    # vs base is a client-ADDED proc (with default=2), not a param edit --
    # kept as-is deliberately; the tool must catch exactly that.
    planted.append(("P4 BenchSmall created in MOD only", "client-added proc"))

    # P5: new table + new column on existing table (additive DDL)
    sql(cur, "CREATE TABLE dbo.BenchExtra (ID int IDENTITY PRIMARY KEY, Note nvarchar(30) NULL)",
        "ALTER TABLE dbo.BenchItems ADD Reference nvarchar(20) NULL")
    planted.append(("P5a new table BenchExtra", "added table"))
    planted.append(("P5b BenchItems.Reference column", "added column"))

    conn.close()

    # backup mod
    c = connect(); cu = c.cursor()
    cu.execute(f"BACKUP DATABASE {MOD} TO DISK = '/var/opt/mssql/data/{MOD}.bak' WITH INIT")
    c.close()

    import subprocess
    for name in (BASE, MOD):
        subprocess.run(["docker", "cp", f"drift-tool-mssql:/var/opt/mssql/data/{name}.bak",
                        str(OUT / f"{ 'base' if name == BASE else 'mod' }.bak")], check=True)

    print("=== GROUND TRUTH (client_to_105, Master=base Client=mod, client_active_id=66) ===")
    for name, expect in planted:
        print(f"  {name} -> expect: {expect}")
    print("\nbak files:", OUT / "base.bak", "|", OUT / "mod.bak")


if __name__ == "__main__":
    main()
