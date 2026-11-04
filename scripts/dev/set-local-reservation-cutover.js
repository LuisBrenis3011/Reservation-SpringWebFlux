'use strict';
const input=JSON.parse(Buffer.from(process.env.EATS_CUTOVER_BASE64||'', 'base64').toString('utf8'));
if(!/^[A-Za-z0-9_-]{1,63}$/.test(input.database)||['admin','local','config'].includes(input.database))throw Error('Base no permitida');
if(!db.getSiblingDB('admin').auth(process.env.MONGO_INITDB_ROOT_USERNAME,process.env.MONGO_INITDB_ROOT_PASSWORD))throw Error('Autenticacion fallida');
const hello=db.adminCommand({hello:1});if(!hello.isWritablePrimary||hello.setName!=='rs0')throw Error('Se requiere rs0 PRIMARY');
const target=db.getSiblingDB(input.database);
const id='managed-reservations-v1',old=target.reservation_policy.findOne({_id:id});
if(old&&(old.legacyWritesRetired!==true||!(old.cutoverAt instanceof Date)))throw Error('Politica invalida; no se sobrescribe');
if(target.reservation_policy.countDocuments({_id:{$ne:id}})!==0)throw Error('Politicas ajenas; revisar');
const indexes=target.reservations.getIndexes();
const expected={rsv_active_table_unique:{restaurantId:1,shiftId:1,tableIds:1},rsv_active_customer_unique:{restaurantId:1,shiftId:1,customerIssuer:1,customerSubject:1}};
for(const [name,key] of Object.entries(expected)){
 const index=indexes.find(i=>i.name===name);
 if(!index?.unique||JSON.stringify(index.key)!==JSON.stringify(key)||JSON.stringify(index.partialFilterExpression)!==JSON.stringify({schemaVersion:2,status:'CONFIRMED'}))throw Error('Indice unico incompatible');
}
for(const name of ['rsv_customer_list','rsv_restaurant_list'])if(!indexes.some(i=>i.name===name))throw Error('Falta indice de listas');
if(!old&&target.reservations.countDocuments({schemaVersion:2})!==0)throw Error('El primer corte no regulariza reservas v2 preexistentes');
if(!old&&target.operation_receipts.countDocuments({idempotencyKey:/^rsv:/})!==0)throw Error('Namespace de recibos reservado ya ocupado');
if(input.apply&&!old)target.reservation_policy.updateOne({_id:id},{$setOnInsert:{legacyWritesRetired:true,cutoverAt:new Date()}},{upsert:true,writeConcern:{w:'majority'}});
print(old?'Corte ya registrado; sin cambios':input.apply?'Corte registrado; gate sin cambios':'Preflight correcto; no se escribio politica. Aplicar exige -Apply');
