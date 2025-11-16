// create initial db
var dbName = 'lunarUniScan';
var dbRef = db.getSiblingDB(dbName);
// touch a collection to ensure creation
if (!dbRef.getCollectionNames().includes('init')) {
  dbRef.createCollection('init');
}
