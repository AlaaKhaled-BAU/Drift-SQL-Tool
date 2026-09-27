"""Windows-authentication connections to the scratch server via pyodbc, shaped like
pymssql connections so restore/inspect/changelog code does not change."""
import re

import pymssql

_PARAM = re.compile(r"%s")


def _driver() -> str:
    import pyodbc
    names = [d for d in pyodbc.drivers() if "SQL Server" in d]
    for preferred in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server"):
        if preferred in names:
            return preferred
    if names:
        return names[-1]
    raise RuntimeError("no SQL Server ODBC driver installed (install ODBC Driver 18 for SQL Server)")


class _Cursor:
    def __init__(self, cur, as_dict):
        self._cur, self._as_dict = cur, as_dict

    def execute(self, sql, params=None):
        sql = _PARAM.sub("?", sql)
        if params is None:
            self._cur.execute(sql)
        else:
            self._cur.execute(sql, tuple(params) if isinstance(params, (list, tuple)) else (params,))
        return self

    def _row(self, row):
        if row is None or not self._as_dict:
            return None if row is None else tuple(row)
        return {d[0]: v for d, v in zip(self._cur.description, row)}

    def fetchone(self):
        return self._row(self._cur.fetchone())

    def fetchall(self):
        return [self._row(r) for r in self._cur.fetchall()]

    def __iter__(self):
        return iter(self.fetchall())


class _Conn:
    def __init__(self, conn):
        self._conn = conn

    def cursor(self, as_dict=False):
        return _Cursor(self._conn.cursor(), as_dict)

    def commit(self):
        self._conn.commit()

    def close(self):
        self._conn.close()


def connect(server, port=None, database=None, autocommit=True, timeout=0, login_timeout=10, **_):
    import pyodbc
    host = server if port is None else f"{server},{port}"
    cs = (f"DRIVER={{{_driver()}}};SERVER={host};Trusted_Connection=yes;"
          f"TrustServerCertificate=yes;DATABASE={database or 'master'}")
    try:
        conn = pyodbc.connect(cs, autocommit=autocommit, timeout=login_timeout)
    except pyodbc.Error as e:
        raise pymssql.OperationalError(str(e)) from e
    if timeout:
        conn.timeout = timeout
    return _Conn(conn)
