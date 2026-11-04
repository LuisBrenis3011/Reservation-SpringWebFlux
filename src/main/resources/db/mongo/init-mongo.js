db.createCollection('restaurants', { capped: false });

db.restaurants.insert([
    {
        "_id": UUID("dfcbe98d-392b-4b93-9a49-27005223d15d"),
        "name": "The Golden Spoon",
        "capacity": 75,
        "address": {
            "street": "123 Culinary Ave",
            "city": "New York",
            "postalCode": "10001"
        },
        "cuisineType": "Italian",
        "priceRange": "CHEAP",
        "openHours": "12:00-23:00",
        "logoUrl": "https://example.com/logos/golden-spoon.png",
        "contactInfo": {
            "phone": "+1 212-555-1234",
            "email": "info@goldenspoon.com",
            "website": "www.goldenspoon.com"
        },
        "reviews": [
            {
                "customerId": "aaaf14a7-b53f-4017-9e59-4e8a741f6c74",
                "customerName": "Michael Rodriguez",
                "rating": 5,
                "comment": "The pasta was perfectly al dente. One of the best Italian restaurants in the city.",
                "timestamp": "2024-12-01T13:06:43.941226Z"
            },
            {
                "customerId": "79f2296f-24d8-4ab3-b812-9ffe5c3e983d",
                "customerName": "Anna Guzman",
                "rating": 4,
                "comment": "A bit noisy for my taste, but the food is excellent. The ricotta ravioli is incredible.",
                "timestamp": "2025-01-19T19:16:43.941515Z"
            },
            {
                "customerId": "995e9b78-1583-45c6-b3ca-1501691e9880",
                "customerName": "Robert Fields",
                "rating": 4,
                "comment": "Service was a little slow, but the quality of the food makes up for it. I recommend the risotto.",
                "timestamp": "2025-03-20T20:26:43.941579Z"
            }
        ]
    },
    {
        "_id": UUID("0ee619ba-e95f-4103-99f7-ee9cdf831d90"),
        "name": "La Parrilla Moderna",
        "capacity": 80,
        "address": {
            "street": "456 Gourmet Blvd",
            "city": "Chicago",
            "postalCode": "60601"
        },
        "cuisineType": "Mexican",
        "priceRange": "MEDIUM",
        "openHours": "11:00-22:00",
        "logoUrl": "https://example.com/logos/la-parrilla.png",
        "contactInfo": {
            "phone": "+1 312-555-6789",
            "email": "hello@laparrilla.com",
            "website": "www.laparrilla.com"
        },
        "reviews": [
            {
                "customerId": "65429e2e-686d-49fe-9f0c-4982c3c06d5d",
                "customerName": "Caroline Mendez",
                "rating": 5,
                "comment": "Best al pastor tacos I've ever tried. The atmosphere is very traditional and cozy.",
                "timestamp": "2025-02-04T18:15:43.941776Z"
            },
            {
                "customerId": "eff0ff42-b4df-46f9-bfca-209fb8857d1c",
                "customerName": "Daniel Hernandez",
                "rating": 3,
                "comment": "Not impressed with the enchiladas, but their guacamole was fresh and delicious.",
                "timestamp": "2025-02-05T20:45:43.941793Z"
            },
            {
                "customerId": "ef067730-da76-4800-bc95-a859c7a16f10",
                "customerName": "Emily Wilson",
                "rating": 5,
                "comment": "One of the best meals I've had! The mole sauce is to die for.",
                "timestamp": "2024-12-10T19:30:43.941810Z"
            }
        ]
    },
    {
        "_id": UUID("fa7b71e6-788e-460d-b8c1-0a59bfea2ea2"),
        "name": "Sushi Zen",
        "capacity": 50,
        "address": {
            "street": "789 Flavor St",
            "city": "Los Angeles",
            "postalCode": "90001"
        },
        "cuisineType": "Japanese",
        "priceRange": "EXPENSIVE",
        "openHours": "17:00-23:00",
        "logoUrl": "https://example.com/logos/sushi-zen.png",
        "contactInfo": {
            "phone": "+1 213-555-4321",
            "email": "info@sushizen.com",
            "website": "www.sushi-zen.com"
        },
        "reviews": [
            {
                "customerId": "24d52513-ec71-4fd0-a99b-cdf99818504b",
                "customerName": "Jessica Park",
                "rating": 5,
                "comment": "The sashimi is incredibly fresh. Chef Tanaka is truly a master of his craft.",
                "timestamp": "2024-12-18T21:15:43.942100Z"
            },
            {
                "customerId": "cc79e7ed-0d30-4051-9ae3-28077a8c7224",
                "customerName": "Thomas Wright",
                "rating": 5,
                "comment": "Best omakase experience in the city. Worth every penny!",
                "timestamp": "2025-02-17T20:10:43.942114Z"
            },
            {
                "customerId": "af777140-e3f0-414c-8751-dc842c56422f",
                "customerName": "Olivia Johnson",
                "rating": 4,
                "comment": "The dragon roll was exceptional. Slightly pricey but the quality justifies it.",
                "timestamp": "2025-01-26T19:45:43.942159Z"
            }
        ]
    },
    {
        "_id": UUID("41c599c0-4b1d-476b-92a6-5cd1804333b3"),
        "name": "Pasta Fresca",
        "capacity": 120,
        "address": {
            "street": "321 Fusion Ln",
            "city": "Boston",
            "postalCode": "02108"
        },
        "cuisineType": "Italian",
        "priceRange": "MEDIUM",
        "openHours": "11:30-22:30",
        "logoUrl": "https://example.com/logos/pasta-fresca.png",
        "contactInfo": {
            "phone": "+1 617-555-8765",
            "email": "reservations@pastafresca.com",
            "website": "www.pastafresca.com"
        },
        "reviews": [
            {
                "customerId": "b7ab3b3d-2ab3-4f14-99fa-bcefa10387e8",
                "customerName": "Nathan Brown",
                "rating": 5,
                "comment": "Their homemade pappardelle with wild boar ragù is simply spectacular.",
                "timestamp": "2024-12-01T18:30:43.942268Z"
            },
            {
                "customerId": "04692341-2788-4d1f-a841-866752e27d46",
                "customerName": "Sarah Miller",
                "rating": 4,
                "comment": "Amazing atmosphere and attentive service. The tiramisu was heavenly.",
                "timestamp": "2024-12-16T20:00:43.942283Z"
            },
            {
                "customerId": "07b988ec-5350-4acc-8ce8-c3aa8b4258b9",
                "customerName": "Kevin Taylor",
                "rating": 5,
                "comment": "One of the best Italian restaurants I've been to outside of Italy. Authentic flavors!",
                "timestamp": "2024-11-30T19:15:43.942297Z"
            }
        ]
    },
    {
        "_id": UUID("f9f583fd-d362-4dae-bc8a-c44cab8a5fd4"),
        "name": "Taco Revolución",
        "capacity": 100,
        "address": {
            "street": "654 Herb Rd",
            "city": "Austin",
            "postalCode": "78701"
        },
        "cuisineType": "Mexican",
        "priceRange": "CHEAP",
        "openHours": "10:00-22:00",
        "logoUrl": "https://example.com/logos/taco-revolucion.png",
        "contactInfo": {
            "phone": "+1 512-555-9876",
            "email": "hola@tacorevolucion.com",
            "website": "www.tacorevolucion.com"
        },
        "reviews": [
            {
                "customerId": "b51e9745-9caf-4ef9-b7e4-b4257f5148b4",
                "customerName": "Alex Martinez",
                "rating": 4,
                "comment": "Authentic street tacos at affordable prices. The salsa bar is impressive!",
                "timestamp": "2025-02-08T12:30:43.942600Z"
            },
            {
                "customerId": "77050f99-c1a7-4636-b307-46a6798f4f6b",
                "customerName": "Sophia Garcia",
                "rating": 5,
                "comment": "The birria tacos are life-changing. Don't miss their horchata!",
                "timestamp": "2024-12-12T13:45:43.942614Z"
            },
            {
                "customerId": "ae14cb3d-1f79-4f2c-a3b8-e1a7cd69f873",
                "customerName": "William Chang",
                "rating": 4,
                "comment": "Great value for money. The carnitas tacos are particularly good.",
                "timestamp": "2024-11-29T19:00:43.942628Z"
            }
        ]
    },
    {
        "_id": UUID("a4733f6e-82a2-4fa0-acdd-62d9cb6b9aff"),
        "name": "Steakhouse 212",
        "capacity": 60,
        "address": {
            "street": "987 Grill Pkwy",
            "city": "Dallas",
            "postalCode": "75201"
        },
        "cuisineType": "American",
        "priceRange": "EXPENSIVE",
        "openHours": "17:00-23:00",
        "logoUrl": "https://example.com/logos/steakhouse-212.png",
        "contactInfo": {
            "phone": "+1 214-555-2468",
            "email": "info@steakhouse212.com",
            "website": "www.steakhouse212.com"
        },
        "reviews": [
            {
                "customerId": "790617d4-3f69-4b33-8368-2d0bab9bbdc2",
                "customerName": "James Wilson",
                "rating": 5,
                "comment": "The dry-aged ribeye was perfectly cooked. Worth every penny.",
                "timestamp": "2024-11-14T20:45:43.942749Z"
            },
            {
                "customerId": "22dad7b9-a02d-405f-a4b4-4b66bf9aa50d",
                "customerName": "Elizabeth Scott",
                "rating": 5,
                "comment": "Impeccable service and the best filet mignon I've ever had.",
                "timestamp": "2024-12-26T19:15:43.942767Z"
            },
            {
                "customerId": "b0943c4a-d17b-40b9-a7a5-3f345627c3df",
                "customerName": "Ryan Thompson",
                "rating": 4,
                "comment": "Excellent wine selection that pairs perfectly with their steaks.",
                "timestamp": "2025-03-04T18:30:43.942781Z"
            }
        ]
    },
    {
        "_id": UUID("5deeb520-dff6-4552-9d97-119e84b5a704"),
        "name": "Vegan Vibes",
        "capacity": 90,
        "address": {
            "street": "159 Organic Way",
            "city": "Portland",
            "postalCode": "97201"
        },
        "cuisineType": "Vegan",
        "priceRange": "MEDIUM",
        "openHours": "08:00-21:00",
        "logoUrl": "https://example.com/logos/vegan-vibes.png",
        "contactInfo": {
            "phone": "+1 503-555-1357",
            "email": "hello@veganvibes.com",
            "website": "www.veganvibes.com"
        },
        "reviews": [
            {
                "customerId": "2a9c5b93-afc7-4e3f-bdd8-21b6404031ad",
                "customerName": "Madison Green",
                "rating": 5,
                "comment": "Their jackfruit pulled 'pork' sandwich is incredible. You won't miss meat here!",
                "timestamp": "2025-04-05T12:00:43.942945Z"
            },
            {
                "customerId": "b7e4377a-94be-47f4-965f-f385cc2abf86",
                "customerName": "David Cooper",
                "rating": 4,
                "comment": "Amazing plant-based dishes. The cashew cheese sauce is outstanding.",
                "timestamp": "2024-10-27T13:15:43.942960Z"
            },
            {
                "customerId": "bc06eeda-3f0c-4408-b8a2-2c8bda71c64a",
                "customerName": "Rachel Kim",
                "rating": 5,
                "comment": "As a non-vegan, I was blown away by the creativity and flavor in every dish.",
                "timestamp": "2025-01-25T11:30:43.942975Z"
            }
        ]
    },
    {
        "_id": UUID("be33011c-13dd-45b9-a60e-e9adb8f4e022"),
        "name": "Café Nostalgia",
        "capacity": 65,
        "address": {
            "street": "753 Espresso Ct",
            "city": "Seattle",
            "postalCode": "98101"
        },
        "cuisineType": "French",
        "priceRange": "MEDIUM",
        "openHours": "07:00-22:00",
        "logoUrl": "https://example.com/logos/cafe-nostalgia.png",
        "contactInfo": {
            "phone": "+1 206-555-7531",
            "email": "bonjour@cafenostalgia.com",
            "website": "www.cafenostalgia.com"
        },
        "reviews": [
            {
                "customerId": "430e4343-fe89-465f-8619-3a59c0e8e10f",
                "customerName": "Charlotte Davis",
                "rating": 5,
                "comment": "Their croissants are as authentic as what you'd find in Paris. The coffee is exceptional too.",
                "timestamp": "2024-10-23T09:15:43.943037Z"
            },
            {
                "customerId": "9d71a410-0897-430d-ae47-73d2a9a0d687",
                "customerName": "Benjamin Moore",
                "rating": 4,
                "comment": "Cozy atmosphere perfect for a rainy Seattle morning. The croque madame is fantastic.",
                "timestamp": "2024-11-10T10:30:43.943052Z"
            },
            {
                "customerId": "3bffd0f0-e106-41d2-9c75-5e3371de546a",
                "customerName": "Nicole Adams",
                "rating": 5,
                "comment": "The best French pastries in the city, hands down. Their chocolate éclairs are divine.",
                "timestamp": "2024-12-14T15:45:43.943066Z"
            }
        ]
    }
]);

db.createCollection('reservations', { capped: false });

db.reservations.insert([
    {
        "_id": UUID("4bb269b3-5700-4f85-8a1f-333991ab376d"),
        "restaurantId": UUID("dfcbe98d-392b-4b93-9a49-27005223d15d"),
        "customerId": "b321043e-adfc-48b5-b9f7-e9769701e886",
        "customerName": "Laura Thompson",
        "customerEmail": "laura.thompson@email.com",
        "time": "19:30",
        "partySize": 4,
        "status": "CONFIRMED",
        "notes": "Window seat requested"
    },
    {
        "_id": UUID("0db5a734-f37d-48b1-b3a1-03fda97806bb"),
        "restaurantId": UUID("dfcbe98d-392b-4b93-9a49-27005223d15d"),
        "customerId": "50726950-7ac7-4ddd-88d1-cad6e9751033",
        "customerName": "John Davis",
        "customerEmail": "john.davis@email.com",
        "time": "18:00",
        "partySize": 2,
        "status": "CONFIRMED",
        "notes": "Anniversary celebration"
    },
    {
        "_id": UUID("06046369-c4a3-40a7-9940-8fd61267f70a"),
        "restaurantId": UUID("dfcbe98d-392b-4b93-9a49-27005223d15d"),
        "customerId": "4eb97bf5-c51f-4924-8fb8-5c6eea2ac9e9",
        "customerName": "Maria Rodriguez",
        "customerEmail": "maria.r@email.com",
        "time": "20:00",
        "partySize": 6,
        "status": "pending",
        "notes": "Birthday celebration, cake will be brought"
    },
    {
        "_id": UUID("edfc9671-db75-42d5-a44a-b278ead8b7fb"),
        "restaurantId": UUID("0ee619ba-e95f-4103-99f7-ee9cdf831d90"),
        "customerId": "782034cd-c6a1-42ee-ac84-4c3fc6c50ba4",
        "customerName": "Robert Johnson",
        "customerEmail": "robert.j@email.com",
        "time": "19:00",
        "partySize": 4,
        "status": "CONFIRMED",
        "notes": "Prefer table away from kitchen"
    },
    {
        "_id": UUID("729075ed-2a70-4ab0-b584-45aed7a4647f"),
        "restaurantId": UUID("0ee619ba-e95f-4103-99f7-ee9cdf831d90"),
        "customerId": "1e649f77-62e2-42ab-827b-34cda41b2ddc",
        "customerName": "Jennifer Wilson",
        "customerEmail": "jen.wilson@email.com",
        "time": "18:30",
        "partySize": 2,
        "status": "confirmed",
        "notes": ""
    },
    {
        "_id": UUID("d3cc8c09-3bfa-4cd4-89f3-ea8e86914eb5"),
        "restaurantId": UUID("fa7b71e6-788e-460d-b8c1-0a59bfea2ea2"),
        "customerId": "8fd42c90-f22b-4272-8080-aba13a15210f",
        "customerName": "Michael Chen",
        "customerEmail": "michael.chen@email.com",
        "time": "20:00",
        "partySize": 3,
        "status": "confirmed",
        "notes": "Sushi bar seating preferred"
    },
    {
        "_id": UUID("cf41c463-c2e3-4948-aa6a-019e18ea4ab4"),
        "restaurantId": UUID("fa7b71e6-788e-460d-b8c1-0a59bfea2ea2"),
        "customerId": "ce9738fd-b7a4-4af7-94c4-acdcf95100d5",
        "customerName": "Emily Jackson",
        "customerEmail": "emily.j@email.com",
        "time": "19:30",
        "partySize": 2,
        "status": "confirmed",
        "notes": "First time visitors, omakase experience"
    },
    {
        "_id": UUID("0b850266-65d4-4011-a224-6a0073ed6902"),
        "restaurantId": UUID("fa7b71e6-788e-460d-b8c1-0a59bfea2ea2"),
        "customerId": "3f8e2606-53ee-42d7-8616-659445fc9c74",
        "customerName": "David Kim",
        "customerEmail": "david.kim@email.com",
        "time": "20:30",
        "partySize": 4,
        "status": "pending",
        "notes": "Celebrating graduation"
    },
    {
        "_id": UUID("6c37a0e8-332b-4a0c-8945-fd80215e8500"),
        "restaurantId": UUID("41c599c0-4b1d-476b-92a6-5cd1804333b3"),
        "customerId": "1528bfb8-c044-4461-ab74-c7db0a2cdbeb",
        "customerName": "Thomas Miller",
        "customerEmail": "thomas.m@email.com",
        "time": "19:00",
        "partySize": 5,
        "status": "confirmed",
        "notes": "Business dinner"
    },
    {
        "_id": UUID("a049419c-1084-492c-b8f4-45a17f1967f3"),
        "restaurantId": UUID("41c599c0-4b1d-476b-92a6-5cd1804333b3"),
        "customerId": "c29804b7-abc3-4487-bd8c-e80d974f0221",
        "customerName": "Samantha Lee",
        "customerEmail": "sam.lee@email.com",
        "time": "20:30",
        "partySize": 3,
        "status": "confirmed",
        "notes": "Gluten-free options needed"
    },
    {
        "_id": UUID("e932eaf7-bd57-4cda-b502-8c26396188c4"),
        "restaurantId": UUID("f9f583fd-d362-4dae-bc8a-c44cab8a5fd4"),
        "customerId": "547d6f90-030e-43bd-b6d1-209a72976bfa",
        "customerName": "Carlos Morales",
        "customerEmail": "carlos.m@email.com",
        "time": "18:00",
        "partySize": 4,
        "status": "confirmed",
        "notes": "Outdoor seating if available"
    },
    {
        "_id": UUID("64ac2cb5-a0b7-4aa6-ad61-4fcde0113b3e"),
        "restaurantId": UUID("f9f583fd-d362-4dae-bc8a-c44cab8a5fd4"),
        "customerId": "7c0a31df-e006-4bc9-812f-6a808b4c1470",
        "customerName": "Angela Martinez",
        "customerEmail": "angela.m@email.com",
        "time": "19:00",
        "partySize": 2,
        "status": "confirmed",
        "notes": "First anniversary"
    },
    {
        "_id": UUID("2983cb6f-553e-4045-8f9f-12e9a28b33be"),
        "restaurantId": UUID("a4733f6e-82a2-4fa0-acdd-62d9cb6b9aff"),
        "customerId": "fe52f0a0-90e4-4284-a3cf-4b53288cf6c8",
        "customerName": "William Barnes",
        "customerEmail": "will.barnes@email.com",
        "time": "19:30",
        "partySize": 6,
        "status": "confirmed",
        "notes": "Corporate dinner"
    },
    {
        "_id": UUID("4933176f-f614-4abd-a4bc-08db4d64645e"),
        "restaurantId": UUID("a4733f6e-82a2-4fa0-acdd-62d9cb6b9aff"),
        "customerId": "b2a26ca2-f11a-4319-8a7f-b42db8f1b5c2",
        "customerName": "Katherine Robinson",
        "customerEmail": "kathy.r@email.com",
        "time": "20:00",
        "partySize": 2,
        "status": "confirmed",
        "notes": "Anniversary - please provide a special dessert"
    },
    {
        "_id": UUID("4e80d02a-c4f0-4e9e-8254-5ecfca5b6f84"),
        "restaurantId": UUID("a4733f6e-82a2-4fa0-acdd-62d9cb6b9aff"),
        "customerId": "c1fae491-fb31-4826-a279-a54b3d2e6491",
        "customerName": "James Peterson",
        "customerEmail": "james.p@email.com",
        "time": "21:00",
        "partySize": 4,
        "status": "pending",
        "notes": "Client meeting"
    },
    {
        "_id": UUID("b34b8755-12fc-4c51-99ef-503d6cba2e78"),
        "restaurantId": UUID("5deeb520-dff6-4552-9d97-119e84b5a704"),
        "customerId": "059a8767-d6fd-430d-8355-04f80de7ed30",
        "customerName": "Emma Davis",
        "customerEmail": "emma.d@email.com",
        "time": "12:30",
        "partySize": 3,
        "status": "confirmed",
        "notes": "Severe nut allergy"
    },
    {
        "_id": UUID("a0b93b40-a385-46cb-beae-638d14b7971e"),
        "restaurantId": UUID("5deeb520-dff6-4552-9d97-119e84b5a704"),
        "customerId": "29b66fca-f9cc-46b9-9f1c-50326e0c9cac",
        "customerName": "Steven Walsh",
        "customerEmail": "steve.w@email.com",
        "time": "13:00",
        "partySize": 2,
        "status": "confirmed",
        "notes": "First time trying vegan cuisine"
    },
    {
        "_id": UUID("2927fc68-699e-4694-a612-11142b19286a"),
        "restaurantId": UUID("5deeb520-dff6-4552-9d97-119e84b5a704"),
        "customerId": "28dfe88e-ee52-47ae-95b3-c073bd78a8ff",
        "customerName": "Melissa Young",
        "customerEmail": "melissa.y@email.com",
        "time": "18:30",
        "partySize": 5,
        "status": "confirmed",
        "notes": "Celebrating new job"
    },
    {
        "_id": UUID("acf14684-4250-4498-b8f5-bb1bb6b5fd54"),
        "restaurantId": UUID("be33011c-13dd-45b9-a60e-e9adb8f4e022"),
        "customerId": "09a4bd2e-090d-4a8b-b6f6-d255ad327bcd",
        "customerName": "Christopher Hughes",
        "customerEmail": "chris.h@email.com",
        "time": "09:30",
        "partySize": 2,
        "status": "confirmed",
        "notes": "Business breakfast"
    },
    {
        "_id": UUID("ab2e6073-fc09-42c2-8c36-b93387f62351"),
        "restaurantId": UUID("be33011c-13dd-45b9-a60e-e9adb8f4e022"),
        "customerId": "777e2c3d-2109-4acd-932f-ba533d2d68c9",
        "customerName": "Michelle Parker",
        "customerEmail": "michelle.p@email.com",
        "time": "16:00",
        "partySize": 3,
        "status": "confirmed",
        "notes": "High tea service"
    },
    {
        "_id": UUID("6c608824-210a-45f0-9fe9-6241985959e7"),
        "restaurantId": UUID("be33011c-13dd-45b9-a60e-e9adb8f4e022"),
        "customerId": "f7e4e182-a623-4eac-844b-1034beaf1cb8",
        "customerName": "Daniel Foster",
        "customerEmail": "daniel.f@email.com",
        "time": "18:30",
        "partySize": 4,
        "status": "pending",
        "notes": "Quiet table for discussion"
    }
]);

db.restaurants.updateOne(
    { "_id": UUID("dfcbe98d-392b-4b93-9a49-27005223d15d") }, // The Golden Spoon
    { $set: { "closeAt": "22:00" } }
);

db.restaurants.updateOne(
    { "_id": UUID("0ee619ba-e95f-4103-99f7-ee9cdf831d90") }, // La Parrilla Moderna
    { $set: { "closeAt": "22:00" } }
);

db.restaurants.updateOne(
    { "_id": UUID("fa7b71e6-788e-460d-b8c1-0a59bfea2ea2") }, // Sushi Zen
    { $set: { "closeAt": "21:00" } }
);

db.restaurants.updateOne(
    { "_id": UUID("41c599c0-4b1d-476b-92a6-5cd1804333b3") }, // Pasta Fresca
    { $set: { "closeAt": "21:00" } }
);

db.restaurants.updateOne(
    { "_id": UUID("f9f583fd-d362-4dae-bc8a-c44cab8a5fd4") }, // Taco Revolución
    { $set: { "closeAt": "20:00" } }
);

db.restaurants.updateOne(
    { "_id": UUID("a4733f6e-82a2-4fa0-acdd-62d9cb6b9aff") }, // Steakhouse 212
    { $set: { "closeAt": "21:00" } }
);

db.restaurants.updateOne(
    { "_id": UUID("5deeb520-dff6-4552-9d97-119e84b5a704") }, // Vegan Vibes
    { $set: { "closeAt": "21:00" } }
);

db.restaurants.updateOne(
    { "_id": UUID("be33011c-13dd-45b9-a60e-e9adb8f4e022") }, // Café Nostalgia
    { $set: { "closeAt": "21:00" } }
);

