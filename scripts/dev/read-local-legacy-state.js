// Solo lectura y solo restaurantes ficticios A/B. No imprime datos personales.
const name = process.env.EATS_BACKUP_DATABASE;
if (!name || !/^[A-Za-z0-9_-]{1,63}$/.test(name) || ['admin','local','config'].includes(name)) throw Error('Base no permitida');
if (!db.getSiblingDB('admin').auth(process.env.MONGO_INITDB_ROOT_USERNAME,
    process.env.MONGO_INITDB_ROOT_PASSWORD)) throw Error('Autenticacion fallida');
const hello = db.adminCommand({hello:1});
if (hello.setName !== 'rs0' || !hello.isWritablePrimary) throw Error('Origen inesperado');
const target = db.getSiblingDB(name);
const a = UUID('11111111-1111-4111-8111-111111111111');
const b = UUID('22222222-2222-4222-8222-222222222222');
for (const id of [a,b]) {
    const restaurant = target.restaurants.findOne({_id:id});
    if (!restaurant || restaurant.localIdentityFixture !== 'eats-hub-local/v1') throw Error('Falta restaurante ficticio');
}
const operation = target.restaurant_operations.findOne({_id:b});
if (!operation) throw Error('Falta revision inicial de B');
const hash = require('crypto').createHash('sha256');
for (const [collection, query] of [ ['restaurants',{_id:a}], ['restaurant_operations',{_id:a}],
    ['restaurant_tables',{restaurantId:a}], ['operation_receipts',{restaurantId:a}],
    ['reservations',{restaurantId:'11111111-1111-4111-8111-111111111111'}] ]) {
    hash.update(collection + '\n');
    target.getCollection(collection).find(query).sort({_id:1}).forEach(row =>
        hash.update(EJSON.stringify(row,null,0,{relaxed:false})+'\n'));
}
let fixture = null;
const id = process.env.EATS_LEGACY_RESERVATION_ID;
if (id) {
    if (!/^[0-9a-f-]{36}$/.test(id)) throw Error('ID de fixture invalido');
    const row = target.reservations.findOne({_id:UUID(id)});
    if (row) {
        if (row.restaurantId !== '22222222-2222-4222-8222-222222222222' ||
            row.customerId !== process.env.EATS_LEGACY_CUSTOMER_ID ||
            row.notes !== process.env.EATS_LEGACY_MARKER) throw Error('Reserva no pertenece a este ensayo');
        fixture = {partySize:Number(row.partySize),date:row.date,time:row.time,status:row.status};
    }
}
print(JSON.stringify({revision:Number(operation.revision),
    reservationCount:target.reservations.countDocuments({restaurantId:'22222222-2222-4222-8222-222222222222'}),
    restaurantASha256:hash.digest('hex'),fixture}));
