import os

from PyCool import cool

if os.path.exists("test_cool.db"):
    os.remove("test_cool.db")
dbSvc = cool.DatabaseSvcFactory.databaseService()
db = dbSvc.createDatabase("sqlite://;schema=test_cool.db;dbname=TESTDB")
spec = cool.RecordSpecification()
spec.extend("x", cool.StorageType.Int32)
folderSpec = cool.FolderSpecification(cool.FolderVersioning.SINGLE_VERSION, spec)
folder = db.createFolder("/test", folderSpec, "a test folder", True)
payload = cool.Record(spec)
payload["x"] = 7
folder.storeObject(0, 10, payload, 0)
db.closeDatabase()

db = dbSvc.openDatabase("sqlite://;schema=test_cool.db;dbname=TESTDB", True)
obj = db.getFolder("/test").findObject(5, 0)
assert obj.payload()["x"] == 7, obj.payload()["x"]
print("COOL SQLite round trip: x =", obj.payload()["x"])
