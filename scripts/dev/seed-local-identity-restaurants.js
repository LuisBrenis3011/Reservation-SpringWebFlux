// Solo fixtures declaradas para el replica set local; nunca se actualizan datos existentes.
const databaseName = process.env.EATS_HUB_SEED_DATABASE;
if (!databaseName || !/^[A-Za-z0-9_-]{1,63}$/.test(databaseName) ||
    ["admin", "local", "config"].includes(databaseName)) throw new Error("Base de fixtures no permitida");
if (!db.getSiblingDB("admin").auth(process.env.MONGO_INITDB_ROOT_USERNAME,
                                  process.env.MONGO_INITDB_ROOT_PASSWORD)) throw new Error("Autenticacion local fallida");
const hello = db.adminCommand({hello:1});
if (hello.setName !== "rs0" || !hello.isWritablePrimary) throw new Error("Se requiere rs0 PRIMARY");
const target = db.getSiblingDB(databaseName);
if (!target.getCollectionNames().includes("restaurants")) target.createCollection("restaurants");
const fixtures = [
  ["11111111-1111-4111-8111-111111111111", "A"],
  ["22222222-2222-4222-8222-222222222222", "B"]
].map(([id, suffix]) => ({
  _id: UUID(id), name: "Eats Hub Demo " + suffix, capacity: 12,
  address: {street: "Demo " + suffix, city: "Lima", postalCode: "15001"},
  cuisineType: "PERUANA", priceRange: "MEDIUM", openHours: "08:00", closeAt: "23:59",
  logoUrl: "", contactInfo: {phone:"000000000", email:"demo-" + suffix.toLowerCase() + "@example.test",
                           website:"https://example.test"}, reviews:[],
  localIdentityFixture: "eats-hub-local/v1"
}));
const session = db.getMongo().startSession();
try {
  session.withTransaction(() => {
    const collection = session.getDatabase(databaseName).restaurants;
    for (const fixture of fixtures) {
      const existing = collection.findOne({_id:fixture._id});
      if (existing && (existing.localIdentityFixture !== fixture.localIdentityFixture ||
                       existing.name !== fixture.name)) throw new Error("Colision con restaurante ajeno: " + fixture._id);
    }
    for (const fixture of fixtures)
      collection.updateOne({_id:fixture._id}, {$setOnInsert:fixture}, {upsert:true});
  }, {readConcern:{level:"snapshot"}, writeConcern:{w:"majority"}});
  print("Restaurantes locales A/B verificados; documentos anteriores conservados.");
} finally { session.endSession(); }
