// Lectura exclusivamente; no modifica politica ni documentos.
const name=process.env.EATS_BACKUP_DATABASE;
if(!name||!/^[A-Za-z0-9_-]{1,63}$/.test(name)||['admin','local','config'].includes(name))throw Error('Base no permitida');
if(process.env.EATS_BACKUP_SOURCE==='true'){
 if(!db.getSiblingDB('admin').auth(process.env.MONGO_INITDB_ROOT_USERNAME,process.env.MONGO_INITDB_ROOT_PASSWORD))throw Error('Autenticacion fallida');
 const h=db.adminCommand({hello:1});if(h.setName!=='rs0'||!h.isWritablePrimary)throw Error('Se requiere rs0 PRIMARY');
}
const target=db.getSiblingDB(name),rows=target.reservation_policy.find({}).toArray();
if(rows.length>1||rows.some(p=>p._id!=='managed-reservations-v1'||p.legacyWritesRetired!==true||!(p.cutoverAt instanceof Date)))throw Error('Politica invalida');
const retired=rows.length===1;
if(!retired&&(target.reservations.countDocuments({schemaVersion:2})||target.operation_receipts.countDocuments({idempotencyKey:/^rsv:/})))throw Error('Datos gestionados sin corte verificable');
if(process.env.EATS_MANAGED_PROOF==='true'&&retired){
 const indexes=target.reservations.getIndexes();
 for(const [n,k] of Object.entries({rsv_active_table_unique:{restaurantId:1,shiftId:1,tableIds:1},rsv_active_customer_unique:{restaurantId:1,shiftId:1,customerIssuer:1,customerSubject:1}})){
  const i=indexes.find(i=>i.name===n);
  if(!i?.unique||JSON.stringify(i.key)!==JSON.stringify(k)||JSON.stringify(i.partialFilterExpression)!==JSON.stringify({schemaVersion:2,status:'CONFIRMED'}))throw Error('Indice gestionado incompatible');
 }
 const receiptIndex=target.operation_receipts.getIndexes().find(i=>i.unique&&JSON.stringify(i.key)===JSON.stringify({restaurantId:1,idempotencyKey:1}));
 if(!receiptIndex)throw Error('Indice unico de recibos ausente');
 for(const n of ['rsv_customer_list','rsv_restaurant_list'])if(!indexes.some(i=>i.name===n))throw Error('Indice de consulta ausente');
}
print(JSON.stringify({verified:true,retired,policy:rows.length?EJSON.stringify(rows[0],null,0,{relaxed:false}):null,managedReservations:target.reservations.countDocuments({schemaVersion:2}),managedReceipts:target.operation_receipts.countDocuments({idempotencyKey:/^rsv:/})}));
