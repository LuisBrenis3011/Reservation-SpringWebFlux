// Solo lectura. Los documentos se comparan mediante EJSON canonico y SHA-256;
// no se imprimen cuerpos, credenciales ni datos personales.
const databaseName = process.env.EATS_BACKUP_DATABASE;
if (!databaseName || !/^[A-Za-z0-9_-]{1,63}$/.test(databaseName) ||
    ['admin', 'local', 'config'].includes(databaseName)) throw new Error('Base no permitida');
if (process.env.EATS_BACKUP_SOURCE === 'true') {
    if (!db.getSiblingDB('admin').auth(process.env.MONGO_INITDB_ROOT_USERNAME,
                                     process.env.MONGO_INITDB_ROOT_PASSWORD)) throw new Error('Autenticacion fallida');
    const hello = db.adminCommand({hello: 1});
    if (hello.setName !== 'rs0' || !hello.isWritablePrimary) throw new Error('Origen requiere rs0 PRIMARY');
}
const crypto = require('crypto');
const target = db.getSiblingDB(databaseName);
const infos = target.getCollectionInfos().sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
const collections = [];
for (const info of infos) {
    if (info.type !== 'collection' || info.options?.timeseries || info.name.startsWith('system.')) {
        throw new Error('Este ensayo solo admite colecciones ordinarias de aplicacion');
    }
    const hash = crypto.createHash('sha256');
    let count = 0;
    target.getCollection(info.name).find({}).sort({_id: 1}).forEach(document => {
        hash.update(EJSON.stringify(document, null, 0, {relaxed: false}) + '\n');
        count++;
    });
    const indexes = target.getCollection(info.name).getIndexes()
        .sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
    const indexHash = crypto.createHash('sha256');
    for (const index of indexes) {
        delete index.ns;
        // Ordenar metadatos, conservando el orden semantico de los campos de key.
        const normalized = {};
        for (const key of Object.keys(index).sort()) normalized[key] = index[key];
        indexHash.update(EJSON.stringify(normalized, null, 0, {relaxed: false}) + '\n');
    }
    collections.push({name: info.name, count, documentsSha256: hash.digest('hex'),
        indexesSha256: indexHash.digest('hex'), options: EJSON.stringify(info.options, null, 0, {relaxed: false})});
}
print(JSON.stringify({database: databaseName, collections}));
