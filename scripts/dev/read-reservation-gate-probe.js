// Consulta de solo lectura para el UUID inocuo.
const input=process.env.EATS_GATE_PROBE_BASE64;
if(!input||!/^[A-Za-z0-9+/]+={0,2}$/.test(input))throw Error('Entrada Base64 invalida');
let data;try{data=JSON.parse(Buffer.from(input,'base64').toString('utf8'));}catch(_){throw Error('JSON invalido');}
if(!/^[A-Za-z0-9_-]{1,63}$/.test(data.database)||['admin','local','config'].includes(data.database)||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(data.id))throw Error('Parametros invalidos');
if(!db.getSiblingDB('admin').auth(process.env.MONGO_INITDB_ROOT_USERNAME,process.env.MONGO_INITDB_ROOT_PASSWORD))throw Error('Autenticacion fallida');
const hello=db.adminCommand({hello:1});if(hello.setName!=='rs0'||!hello.isWritablePrimary)throw Error('Se requiere rs0 PRIMARY');
const target=db.getSiblingDB(data.database),rows=target.reservation_policy.find({}).toArray();
if(rows.length!==1||rows[0]._id!=='managed-reservations-v1'||rows[0].legacyWritesRetired!==true||!(rows[0].cutoverAt instanceof Date))throw Error('Corte no verificable');
if(target.reservations.countDocuments({_id:{$in:[data.id,UUID(data.id)]}})!==0)throw Error('UUID de prueba ocupado');
print(JSON.stringify({verified:true,retired:true,absent:true}));
