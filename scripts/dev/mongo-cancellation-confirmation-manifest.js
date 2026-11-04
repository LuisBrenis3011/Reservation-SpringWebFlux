// Solo lectura. Canal Base64 para no depender del quoting de argumentos en PowerShell 5.1.
const input = process.env.EATS_CANCELLATION_EXPECTATIONS_BASE64;
if (!input || !/^[A-Za-z0-9+/]+={0,2}$/.test(input)) throw new Error('Expectativas Base64 ausentes o invalidas');
let expected;
try { expected = JSON.parse(Buffer.from(input, 'base64').toString('utf8')); }
catch (_) { throw new Error('Expectativas JSON invalidas'); }
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
if (!uuidPattern.test(expected.restaurantId) || !uuidPattern.test(expected.reservationId) ||
    typeof expected.issuer !== 'string' || typeof expected.subject !== 'string' || typeof expected.key !== 'string' ||
    typeof expected.match !== 'string')
    throw new Error('Expectativas incompletas');
const name = process.env.EATS_BACKUP_DATABASE;
if (!name || !/^[A-Za-z0-9_-]{1,63}$/.test(name) || ['admin','local','config'].includes(name)) throw new Error('Base no permitida');
if (!db.getSiblingDB('admin').auth(process.env.MONGO_INITDB_ROOT_USERNAME, process.env.MONGO_INITDB_ROOT_PASSWORD)) throw new Error('Autenticacion fallida');
const hello = db.adminCommand({hello:1});
if (hello.setName !== 'rs0' || !hello.isWritablePrimary) throw new Error('Se requiere rs0 PRIMARY');
const crypto = require('crypto');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const canonical = value => EJSON.stringify(value,null,0,{relaxed:false});
const owner = canonical(UUID(expected.restaurantId));
const id = canonical(UUID(expected.reservationId));
function uuidText(value) {
    if (typeof value === 'string' && uuidPattern.test(value)) return value;
    const binary=EJSON.serialize(value,{relaxed:false})?.$binary;
    if (!binary || binary.subType !== '04') throw new Error('UUID no verificable');
    const hex=Buffer.from(binary.base64,'base64').toString('hex');
    return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
}
const timestamp=value=>value instanceof Date?value.toISOString():value;
function view(row, storedReservation) {
    return {kind:'MANAGED',id:uuidText(storedReservation?row._id:(row.id??row._id)),restaurantId:uuidText(row.restaurantId),
        owner:storedReservation?{issuer:row.customerIssuer,subject:row.customerSubject}:{issuer:row.owner.issuer,subject:row.owner.subject},
        shiftId:uuidText(row.shiftId),partySize:Number(row.partySize),notes:row.notes,status:row.status,version:Number(row.version),
        tableIds:row.tableIds.map(uuidText),combinationId:row.combinationId?uuidText(row.combinationId):null,assignedCapacity:Number(row.assignedCapacity),
        localStart:row.localStart,localEnd:row.localEnd,zoneId:row.zoneId,startInstant:timestamp(row.startInstant),endInstant:timestamp(row.endInstant),
        createdAt:timestamp(row.createdAt),updatedAt:timestamp(row.updatedAt),cancelledAt:row.cancelledAt?timestamp(row.cancelledAt):null};
}
const receiptKey='rsv:'+hash(JSON.stringify([expected.issuer,expected.subject,expected.key]));
if(!expected.body || !uuidPattern.test(expected.body.shiftId) || !Number.isInteger(expected.body.partySize) || typeof expected.body.notes!=='string')throw new Error('Intencion de confirmacion incompleta');
const intentBody=JSON.stringify({shiftId:expected.body.shiftId,partySize:expected.body.partySize,notes:expected.body.notes});
const fingerprint=hash(JSON.stringify([expected.issuer,expected.subject,'POST',`/restaurants/${expected.restaurantId}/reservations`,intentBody,null]));
const target=db.getSiblingDB(name);
const receiptRows=target.operation_receipts.find({restaurantId:UUID(expected.restaurantId),idempotencyKey:receiptKey}).toArray();
if(receiptRows.length>1)throw new Error('Recibos duplicados');
const receipt=receiptRows[0]??null;
const newId=receipt?canonical(UUID(uuidText(receipt.responseBody.id??receipt.responseBody._id))):null;
const protectedCollections=[];let reservation=null,operation=null;
for(const info of target.getCollectionInfos().sort((a,b)=>a.name.localeCompare(b.name))){
 if(info.type!=='collection'||info.options?.timeseries||info.name.startsWith('system.'))throw new Error('Coleccion no admitida');
 const rows=[];
 target.getCollection(info.name).find({}).sort({_id:1}).forEach(row=>{
  if(info.name==='reservations'&&canonical(row._id)===newId){reservation=row;return;}
  if(info.name==='restaurant_operations'&&canonical(row._id)===owner){operation=row;return;}
  if(info.name==='operation_receipts'&&canonical(row.restaurantId)===owner&&row.idempotencyKey===receiptKey)return;
  rows.push(canonical(row));
 });
 const indexes=target.getCollection(info.name).getIndexes().sort((a,b)=>a.name.localeCompare(b.name)).map(index=>{
  delete index.ns;const normalized={};for(const key of Object.keys(index).sort())normalized[key]=index[key];return canonical(normalized);
 });
 protectedCollections.push({name:info.name,count:rows.length,documentsSha256:hash(rows.join('\n')),indexesSha256:hash(indexes.join('\n')),options:canonical(info.options)});
}
if(!operation)throw new Error('Revision ausente');
const operationInvariant={...operation};delete operationInvariant.revision;
let assignmentValid=false,snapshotValid=false,noOverlap=false;
if(reservation){
 const ids=reservation.tableIds.map(uuidText);
 const tables=target.restaurant_tables.find({restaurantId:UUID(expected.restaurantId)}).toArray();
 const capacities=new Map(tables.map(t=>[uuidText(t._id),Number(t.capacity)]));
 const snapshots=reservation.tableSnapshots??[];
 const sum=snapshots.reduce((n,t)=>n+Number(t.capacity),0);
 const unique=new Set(ids).size===ids.length&&ids.length>0;
 const members=reservation.combinationId?target.table_combinations.findOne({_id:reservation.combinationId,restaurantId:UUID(expected.restaurantId)}):null;
 assignmentValid=unique&&(reservation.combinationId?!!members&&canonical(members.tableIds)===canonical(reservation.tableIds):ids.length===1);
 snapshotValid=assignmentValid&&reservation.schemaVersion===2&&snapshots.length===ids.length&&snapshots.every((s,i)=>uuidText(s.id??s._id)===ids[i]&&Number(s.capacity)>0&&capacities.get(ids[i])===Number(s.capacity))&&sum===Number(reservation.assignedCapacity)&&sum>=reservation.partySize;
 const shift=target.restaurant_shifts.findOne({_id:reservation.shiftId,restaurantId:UUID(expected.restaurantId)});
 snapshotValid=snapshotValid&&!!shift&&['localStart','localEnd','zoneId','startInstant','endInstant'].every(k=>canonical(shift[k])===canonical(reservation[k]));
 noOverlap=!target.reservations.find({restaurantId:reservation.restaurantId,shiftId:reservation.shiftId,schemaVersion:2,status:'CONFIRMED',_id:{$ne:reservation._id}}).toArray().some(r=>r.tableIds.some(id=>ids.includes(uuidText(id))));
}
print(JSON.stringify({protectedCollections,operationInvariantSha256:hash(canonical(operationInvariant)),revision:Number(operation.revision),
 receiptCount:receiptRows.length,receiptFingerprintMatches:receipt?receipt.fingerprint===fingerprint:null,receiptStatus:receipt?receipt.httpStatus:null,
 receiptRevision:receipt?Number(receipt.resultingRevision):null,receiptVersion:receipt?Number(receipt.responseBody.version):null,
 receiptLocation:receipt?(receipt.location??null):null,reservationView:reservation?view(reservation,true):null,receiptView:receipt?view(receipt.responseBody,false):null,
 assignmentValid,snapshotValid,noOverlap}));
