// Solo base sintetica nueva bridge. El controlador copia este archivo y fixture.
const fs = require('fs');
const fixture = JSON.parse(fs.readFileSync('/opt/environment-fixture.json','utf8'));
const target = db.getSiblingDB('bridge');
if(target.getCollectionNames().length) throw Error('La base sintetica no esta vacia');
const uuid = value => UUID(value);
target.restaurants.insertMany([
 {_id:uuid(fixture.restaurantId),name:'Bridge restaurant',capacity:20},
 {_id:uuid(fixture.otherRestaurantId),name:'Other bridge restaurant',capacity:20}
]);
target.restaurant_time_zones.insertOne({_id:uuid(fixture.restaurantId),zoneId:'America/Lima'});
target.reservation_policy.insertOne({_id:'managed-reservations-v1',legacyWritesRetired:true,cutoverAt:ISODate(fixture.createdAt)});
target.reservations.insertOne({_id:fixture.legacyId,restaurantId:fixture.restaurantId,status:'PENDING',customerName:'Bridge legacy',partySize:2,notes:'bridge-legacy-secret',date:'2019-01-01',time:'18:00',customerEmail:'bridge-private@example.test'});
for(const [name,status] of [['confirmedId','CONFIRMED'],['cancelledId','CANCELLED']]) {
 target.reservations.insertOne({_id:uuid(fixture[name]),schemaVersion:2,restaurantId:uuid(fixture.restaurantId),shiftId:uuid(fixture.shiftId),tableIds:[uuid(fixture.tableId)],combinationId:null,
  customerIssuer:fixture.issuer,customerSubject:'bridge-owner',partySize:2,notes:'bridge-managed-secret',status,version:NumberLong(1),localStart:fixture.localStart,localEnd:fixture.localEnd,zoneId:'UTC',
  startInstant:ISODate(fixture.startInstant),endInstant:ISODate(fixture.endInstant),tableSnapshots:[{id:uuid(fixture.tableId),capacity:NumberLong(4)}],assignedCapacity:NumberLong(4),createdAt:ISODate(fixture.createdAt),updatedAt:ISODate(fixture.createdAt),cancelledAt:status==='CANCELLED'?ISODate(fixture.createdAt):null});
}
target.operation_receipts.insertOne({_id:'bridge-receipt',restaurantId:uuid(fixture.restaurantId),idempotencyKey:'rsv:'+('a'.repeat(64)),responseBody:{kind:'MANAGED',id:fixture.confirmedId,status:'CONFIRMED'},httpStatus:201,resultingRevision:NumberLong(1)});
target.restaurant_operations.insertMany([{_id:uuid(fixture.restaurantId),revision:NumberLong(1),schemaVersion:1},{_id:uuid(fixture.otherRestaurantId),revision:NumberLong(0),schemaVersion:1}]);
print(JSON.stringify({seeded:true,database:'bridge'}));
