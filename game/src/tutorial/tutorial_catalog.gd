class_name TutorialCatalog
extends RefCounted
## Stable lesson IDs and read-only objectives. English strings use central catalogs.

const CHAPTERS := [
	"Orientation",
	"Your first settlement",
	"Utilities",
	"Growth and budget",
	"Solving problems",
	"Independent play",
	"Transport",
	"City services",
	"Environment",
	"Disaster practice",
	"Late development",
	"Reticulating Splines"
]

const LESSONS := [
	{
		"id": "a1",
		"chapter": 0,
		"title": "Move the map and zoom",
		"rule": "camera",
		"article": "controls",
		"tool": [17, 0],
		"requires": []
	},
	{
		"id": "a2",
		"chapter": 0,
		"title": "Rotate the city and return",
		"rule": "rotation",
		"article": "controls",
		"tool": [17, 0],
		"requires": []
	},
	{
		"id": "a3",
		"chapter": 0,
		"title": "Try Pause and Turtle speed",
		"rule": "speed",
		"article": "controls",
		"tool": [17, 0],
		"requires": []
	},
	{
		"id": "a4",
		"chapter": 0,
		"title": "Query a tile",
		"rule": "query",
		"article": "query",
		"tool": [16, 0],
		"requires": []
	},
	{
		"id": "b1",
		"chapter": 1,
		"title": "Choose a flat building site",
		"rule": "site",
		"article": "settlement",
		"tool": [16, 0],
		"requires": ["a4"]
	},
	{
		"id": "b2",
		"chapter": 1,
		"title": "Build an available power plant",
		"rule": "power",
		"article": "power",
		"tool": [3, 1],
		"requires": ["b1"]
	},
	{
		"id": "b3",
		"chapter": 1,
		"title": "Build a short road",
		"rule": "road",
		"article": "transport",
		"tool": [6, 0],
		"requires": ["b1"]
	},
	{
		"id": "b4",
		"chapter": 1,
		"title": "Zone homes and workplaces",
		"rule": "zones",
		"article": "growth",
		"tool": [9, 0],
		"requires": ["b3"]
	},
	{
		"id": "b5",
		"chapter": 1,
		"title": "Supply the residential zone with power",
		"rule": "powered",
		"article": "power",
		"tool": [3, 0],
		"requires": [
			"b2",
			"b4"
		]
	},
	{
		"id": "b6",
		"chapter": 1,
		"title": "Let the first residents arrive",
		"rule": "population",
		"article": "growth",
		"tool": [9, 0],
		"requires": ["b5"]
	},
	{
		"id": "c1",
		"chapter": 2,
		"title": "Compare surface and underground",
		"rule": "underground",
		"article": "water",
		"tool": [4, 0],
		"requires": []
	},
	{
		"id": "c2",
		"chapter": 2,
		"title": "Build a water pump",
		"rule": "pump",
		"article": "water",
		"tool": [4, 1],
		"requires": ["b2"]
	},
	{
		"id": "c3",
		"chapter": 2,
		"title": "Connect pipes to the residential zone",
		"rule": "piped",
		"article": "water",
		"tool": [4, 0],
		"requires": ["c2"]
	},
	{
		"id": "c4",
		"chapter": 2,
		"title": "Confirm water delivery",
		"rule": "watered",
		"article": "water",
		"tool": [4, 0],
		"requires": [
			"c3",
			"b5"
		]
	},
	{
		"id": "d1",
		"chapter": 3,
		"title": "Distinguish demand from density",
		"rule": "quiz:demand",
		"article": "growth",
		"tool": [9, 0],
		"requires": []
	},
	{
		"id": "d2",
		"chapter": 3,
		"title": "Extend a zone with positive demand",
		"rule": "expand",
		"article": "growth",
		"tool": [9, 0],
		"requires": ["b5"]
	},
	{
		"id": "d3",
		"chapter": 3,
		"title": "Read the budget forecast",
		"rule": "budget",
		"article": "budget",
		"tool": [16, 0],
		"requires": []
	},
	{
		"id": "d4",
		"chapter": 3,
		"title": "Compare taxes and service funding",
		"rule": "quiz:funding",
		"article": "budget",
		"tool": [16, 0],
		"requires": ["d3"]
	},
	{
		"id": "d5",
		"chapter": 3,
		"title": "Understand bonds without borrowing",
		"rule": "quiz:bond",
		"article": "bonds",
		"tool": [16, 0],
		"requires": []
	},
	{
		"id": "d6",
		"chapter": 3,
		"title": "Review a completed budget period",
		"rule": "period",
		"article": "budget",
		"tool": [16, 0],
		"requires": ["d3"]
	},
	{
		"id": "e1",
		"chapter": 4,
		"title": "Restore power in the practice district",
		"rule": "repair_power",
		"article": "power",
		"tool": [3, 0],
		"requires": []
	},
	{
		"id": "e2",
		"chapter": 4,
		"title": "Restore water in the practice district",
		"rule": "repair_water",
		"article": "water",
		"tool": [4, 0],
		"requires": ["e1"]
	},
	{
		"id": "e3",
		"chapter": 4,
		"title": "Separate demand from access problems",
		"rule": "quiz:access",
		"article": "growth",
		"tool": [16, 0],
		"requires": []
	},
	{
		"id": "e4",
		"chapter": 4,
		"title": "Prioritize a projected deficit",
		"rule": "quiz:deficit",
		"article": "budget",
		"tool": [16, 0],
		"requires": []
	},
	{
		"id": "e5",
		"chapter": 4,
		"title": "Use a data view and query a building",
		"rule": "diagnose",
		"article": "query",
		"tool": [16, 0],
		"requires": []
	},
	{
		"id": "f1",
		"chapter": 5,
		"title": "Save your city under your own name",
		"rule": "save",
		"article": "saving",
		"tool": [16, 0],
		"requires": []
	},
	{
		"id": "f2",
		"chapter": 5,
		"title": "Distinguish city and learning progress",
		"rule": "quiz:save",
		"article": "saving",
		"tool": [16, 0],
		"requires": ["f1"]
	},
	{
		"id": "f3",
		"chapter": 5,
		"title": "Choose your adviser preferences",
		"rule": "advisor",
		"article": "adviser",
		"tool": [16, 0],
		"requires": []
	},
	{
		"id": "f4",
		"chapter": 5,
		"title": "Finish the course and keep building",
		"rule": "finish",
		"article": "saving",
		"tool": [16, 0],
		"requires": []
	},
	{
		"id": "t1",
		"chapter": 6,
		"title": "Inspect traffic and a reachable destination",
		"rule": "traffic",
		"article": "transport",
		"tool": [16, 1],
		"requires": []
	},
	{
		"id": "t2",
		"chapter": 6,
		"title": "Build and connect a railway",
		"rule": "rail",
		"article": "transport",
		"tool": [7, 0],
		"requires": []
	},
	{
		"id": "t3",
		"chapter": 6,
		"title": "Explore highways and neighbor connections",
		"rule": "quiz:transport",
		"article": "transport",
		"tool": [6, 1],
		"requires": []
	},
	{
		"id": "s1",
		"chapter": 7,
		"title": "Compare service coverage views",
		"rule": "coverage",
		"article": "services",
		"tool": [13, 0],
		"requires": []
	},
	{
		"id": "s2",
		"chapter": 7,
		"title": "Inspect a funded city service",
		"rule": "service",
		"article": "services",
		"tool": [13, 0],
		"requires": []
	},
	{
		"id": "s3",
		"chapter": 7,
		"title": "Balance service costs and need",
		"rule": "quiz:services",
		"article": "services",
		"tool": [13, 0],
		"requires": []
	},
	{
		"id": "n1",
		"chapter": 8,
		"title": "Compare pollution and land value",
		"rule": "environment",
		"article": "environment",
		"tool": [14, 0],
		"requires": []
	},
	{
		"id": "n2",
		"chapter": 8,
		"title": "Add a park and inspect its surroundings",
		"rule": "park",
		"article": "environment",
		"tool": [14, 0],
		"requires": []
	},
	{
		"id": "n3",
		"chapter": 8,
		"title": "Distinguish evidence from possible causes",
		"rule": "quiz:environment",
		"article": "environment",
		"tool": [16, 0],
		"requires": []
	},
	{
		"id": "x1",
		"chapter": 9,
		"title": "Start a separate disaster exercise",
		"rule": "disaster_start",
		"article": "disaster",
		"tool": [2, 1],
		"requires": []
	},
	{
		"id": "x2",
		"chapter": 9,
		"title": "Pause and dispatch emergency services",
		"rule": "dispatch",
		"article": "disaster",
		"tool": [2, 1],
		"requires": ["x1"]
	},
	{
		"id": "x3",
		"chapter": 9,
		"title": "Inspect damage and plan rebuilding",
		"rule": "quiz:disaster",
		"article": "disaster",
		"tool": [0, 0],
		"requires": ["x2"]
	},
	{
		"id": "l1",
		"chapter": 10,
		"title": "Open the advanced practice city",
		"rule": "late",
		"article": "late",
		"tool": [3, 1],
		"requires": []
	},
	{
		"id": "l2",
		"chapter": 10,
		"title": "Compare later power plants and their costs",
		"rule": "quiz:late",
		"article": "late",
		"tool": [3, 1],
		"requires": ["l1"]
	},
	{
		"id": "l3",
		"chapter": 10,
		"title": "Inspect ports, airports and rewards",
		"rule": "late_tools",
		"article": "late",
		"tool": [8, 0],
		"requires": ["l1"]
	},
	{
		"id": "r1",
		"chapter": 11,
		"title": "Explore themes, packs and visual effects",
		"rule": "settings",
		"article": "rs",
		"tool": [16, 0],
		"requires": []
	},
	{
		"id": "r2",
		"chapter": 11,
		"title": "Take a photo of your city",
		"rule": "photo",
		"article": "rs",
		"tool": [16, 0],
		"requires": []
	},
	{
		"id": "r3",
		"chapter": 11,
		"title": "Understand saved tree growth and host rules",
		"rule": "quiz:trees",
		"article": "rs",
		"tool": [16, 0],
		"requires": []
	}
]

const ARTICLES := {
	"controls": [
		"Move, zoom and rotate using the toolbar or your configured controls. Try Pause, then Turtle.",
		"Open Settings > Controls to see your actual bindings. Rotation returns to the initial direction after four quarter turns.",
		"Pausing stops simulation. Zoom changes the view, not construction costs or the size of a tile."
	],
	"query": [
		"Query a tile to inspect its contents and the city data behind the graphics.",
		"Use the Query tool and the View menu. Compare the selected tile with the relevant data view.",
		"A colored overlay is an observation, not a command. Return to City view to build with the normal artwork."
	],
	"settlement": [
		"Choose flat, empty land with space for homes, jobs, roads and utilities.",
		"Query the site first. Leave room beside the settlement for a power plant and water supply.",
		"Suggested locations are optional. Any valid site and working connection can satisfy the lesson."
	],
	"power": [
		"Build a power plant that is available in this year, then connect it to your residential zone.",
		"Use Power Lines and the Power view. Check the entire route from the plant to the zone.",
		"A wire alone is not proof of supply. Let the regular power calculation finish; the residential target must actually be powered."
	],
	"water": [
		"Build a powered water pump and connect pipes to your residential zone.",
		"Compare Underground and Water views. Fresh water beside a pump can improve production; check its actual supply.",
		"Pipes and delivered water are different. Check power, the source and continuity, then wait for the regular water calculation."
	],
	"growth": [
		"Zone homes and workplaces near transport. Read RCI demand before expanding.",
		"Positive demand indicates interest in a zone type. Density is the permitted development intensity, not current demand.",
		"If development stalls, check power, transport access and demand. Even with these present, growth is evaluated by the normal simulation and is not guaranteed immediately."
	],
	"budget": [
		"Open Budget and distinguish construction spending, ongoing costs, cash and the annual forecast.",
		"Compare tax rates with service funding. A forecast is an estimate, not money already earned.",
		"Review a completed month before judging a change. A projected deficit calls for checking recurring costs and income before more construction."
	],
	"bonds": [
		"A bond brings cash now and creates interest obligations. This lesson does not require borrowing.",
		"Open Budget to inspect bond payments. Example: a $10,000 bond at 5% costs $500 per year in interest.",
		"The example is arithmetic, not an offered rate. Read the actual loan terms and repayment requirements before accepting a bond."
	],
	"saving": [
		"Save the city through File > Save City As. Choose your own file name.",
		"The city file holds the simulation. Local learning records hold lesson completion and hint preferences separately.",
		"Identical renamed or copied saves retain their local learning record. Older or changed saves are checked again; a missing record never prevents loading the city."
	],
	"adviser": [
		"The optional adviser shows at most three current topics, with a reason and a useful next action.",
		"Choose Off, Important only or All hints. You can dismiss a topic for this session or hide its type.",
		"Confirmed utility outages take priority over the budget forecast and development checks. The adviser never builds, borrows or changes speed for you."
	],
	"transport": [
		"Connect homes and workplaces with transport. Inspect Traffic and use Trip Query for a selected origin.",
		"Rail, highways and public transport have different construction and maintenance costs. Check availability before planning them.",
		"A nearby road is not proof of a successful trip. Use the existing trip inspection; neighbor connections need a route that reaches the map boundary."
	],
	"services": [
		"Compare Police and Fire coverage and query existing services. Review their funding in Budget.",
		"Health and education are long-term services. Build according to observed needs and affordable running costs.",
		"Do not add every service at once. A building, its funding and its measured coverage are distinct facts."
	],
	"environment": [
		"Compare Pollution and Land Value views before and after a change.",
		"Parks, surrounding development and terrain can affect attractiveness. Inspect a specific location instead of assuming a single citywide cause.",
		"A correlation is not proof of the cause. Allow normal recalculation and compare the same location; the adviser does not promise immediate growth."
	],
	"disaster": [
		"This exercise uses a separate practice city. Start Fire explicitly from Disasters when you are ready.",
		"Pause to inspect the situation, select emergency dispatch and place a unit. Resume deliberately to observe its work.",
		"Inspect damage with Query and plan rebuilding. No disaster is triggered automatically in a personal city."
	],
	"late": [
		"Use the separate 2050 practice city to explore later tools without waiting decades.",
		"Compare power plant output, cost and lifetime in the existing chooser. Inspect ports, airports and rewards.",
		"A later year does not grant every reward. Population milestones, available space, connections and normal unlock rules still apply."
	],
	"rs": [
		"Open Settings to explore themes, graphics packs and Visual Enhancements. Try Photo mode from Options.",
		"Color adjustments affect artwork; lighting and other effects have their own controls. Photo mode hides the interface for the saved picture.",
		"Tree growth is a saved simulation option, off by default. In multiplayer the host decides. Guided lessons run only in single-player; multiplayer roles and continuation remain in the existing lobby."
	]
}

const QUESTIONS := {
	"forecast": ["Is the budget forecast an estimate rather than guaranteed income?", true],
	"demand": [
		"Does a positive RCI bar mean that the zone is already densely built?",
		false
	],
	"funding": [
		"Are tax rates and the funding of a service the same setting?",
		false
	],
	"bond": [
		"Does borrowing create future interest obligations?",
		true
	],
	"access": [
		"Can an unpowered zone fail to grow even with positive demand?",
		true
	],
	"deficit": [
		"Should you inspect recurring costs before expanding a city with a projected deficit?",
		true
	],
	"save": [
		"Is tutorial progress stored separately from the city simulation?",
		true
	],
	"services": [
		"Does every available service need to be built immediately?",
		false
	],
	"environment": [
		"Does a high land value guarantee immediate growth?",
		false
	],
	"disaster": [
		"Should a disaster exercise replace a personal city without asking?",
		false
	],
	"late": [
		"Does reaching a later year automatically award every special building?",
		false
	],
	"trees": [
		"Does tree growth change saved forest tiles rather than only their appearance?",
		true
	],
	"transport": [
		"Does a road next to a home guarantee a successful trip?",
		false
	]
}

static func lesson(id: String) -> Dictionary:
	for entry in LESSONS:
		if entry.id == id:
			return entry
	return {}
