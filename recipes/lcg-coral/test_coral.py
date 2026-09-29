import coral

svc = coral.ConnectionService()
session = svc.connect("sqlite_file:test_coral.db", coral.access_Update)
session.transaction().start(False)
schema = session.nominalSchema()
if schema.existsTable("T"):
    schema.dropTable("T")
desc = coral.TableDescription()
desc.setName("T")
desc.insertColumn("X", "int")
desc.insertColumn("S", "string")
schema.createTable(desc)
row = coral.AttributeList()
row.extend("X", "int")
row.extend("S", "string")
row["X"].setData(42)
row["S"].setData("hello")
schema.tableHandle("T").dataEditor().insertRow(row)
session.transaction().commit()

session.transaction().start(True)
query = session.nominalSchema().tableHandle("T").newQuery()
cursor = query.execute()
values = []
while cursor.next():
    current = cursor.currentRow()
    values.append((current["X"].data(), current["S"].data()))
session.transaction().commit()
assert values == [(42, "hello")], values
print("CORAL SQLite round trip:", values)
