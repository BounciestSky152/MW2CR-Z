// Remove the level's own soldiers, keeping their spawners for zombies.
// Enemy spawners are preferred; levels without them (S.S.D.D.) use friendly
// ones switched to the enemy team, so shooting them isn't friendly fire.
nacht_clear_level_ai()
{
	enemies = [];
	others = [];
	foreach( s in getspawnerarray() )
	{
		if( !isdefined( s.classname ) || !issubstr( s.classname, "actor" ) )
			continue;
		if( isdefined( s.team ) && s.team == "axis" )
			enemies[ enemies.size ] = s;
		else
			others[ others.size ] = s;
	}
	level.nacht_spawners = enemies;
	level.nacht_switch_team = false;
	if( enemies.size == 0 )
	{
		level.nacht_spawners = others;
		level.nacht_switch_team = true;
	}
	print( "[nacht] spawners: " + enemies.size + " enemy, " + others.size + " other\n" );
	foreach( ai in getaiarray() )
		ai delete();
}

// Nacht der Untoten replica for Modern Warfare 2 Campaign Remastered (h2-mod).
//
// Builds Nacht's layout out of props and collision already loaded in the
// current map, then runs a Nacht-style zombies mode in it. Start it from the
// NACHT DER UNTOTEN button on the campaign menu, or from the console (~):
//   set nacht_play 1     build Nacht around you and start round 1
//   set nacht_build 1    only build it (you end up in the start room)
//   set nacht_clear 1    stop the game and remove the building
// Everything is printed to the console as well, so send that output if
// something looks wrong.
//
// GENERATED FILE: edit mw2cr_nacht/nacht_template.gsc or layout.py, then run
// python3 mw2cr_nacht/layout.py

main()
{
	setdvarifuninitialized( "nacht_build", 0 );
	setdvarifuninitialized( "nacht_play", 0 );
	setdvarifuninitialized( "nacht_clear", 0 );
	setdvarifuninitialized( "nacht_autostart", 0 );
	setdvarifuninitialized( "nacht_budget", 1100 );
	precacheshader( "white" );
	level.nacht_ents = [];
	level.nacht_pieces = [];
	level.nacht_probe_count = 0;
	level thread nacht_watch();
}

nacht_watch()
{
	while( !isdefined( level.player ) )
		wait 0.1;
	wait 3;

	// Started from the menu: wait for the level's intro to hand over control.
	print( "[nacht] autostart=" + getdvarint( "nacht_autostart" ) + "\n" );
	if( getdvarint( "nacht_autostart" ) != 0 )
	{
		setdvar( "nacht_autostart", 0 );
		nacht_say( "Nacht der Untoten: building in a few seconds..." );
		wait 8;
		setdvar( "nacht_play", 1 );
	}
	else
		nacht_say( "Nacht mod loaded. Console: set nacht_play 1" );

	for( ;; )
	{
		if( getdvarint( "nacht_build" ) != 0 || getdvarint( "nacht_play" ) != 0 )
		{
			play = getdvarint( "nacht_play" ) != 0;
			setdvar( "nacht_build", 0 );
			setdvar( "nacht_play", 0 );
			nacht_clear();
			if( nacht_build() && play )
				level thread nacht_zombies_start();
		}
		if( getdvarint( "nacht_clear" ) != 0 )
		{
			setdvar( "nacht_clear", 0 );
			nacht_clear();
			nacht_say( "Nacht removed." );
		}
		wait 0.25;
	}
}

nacht_say( text )
{
	print( "[nacht] " + text + "\n" );
	if( isdefined( level.player ) )
		iprintln( text );
}

nacht_point( x, y, z, yaw )
{
	s = spawnstruct();
	s.origin = ( x, y, z );
	s.yaw = yaw;
	return s;
}

nacht_box( x0, y0, z0, x1, y1, z1, kind, tag )
{
	s = spawnstruct();
	s.mins = ( x0, y0, z0 );
	s.maxs = ( x1, y1, z1 );
	s.kind = kind;
	s.tag = tag;
	return s;
}

// ---------------------------------------------------------------------------
// Building

nacht_build()
{
	points = nacht_points();
	// Put the player where Nacht's spawn is, on the ground they stand on.
	anchor = level.player.origin - points[ "player_start" ].origin + ( 0, 0, 8 );
	anchor = ( int( anchor[0] ), int( anchor[1] ), int( anchor[2] ) );
	level.nacht_anchor = anchor;

	kit = nacht_pick_kit();
	if( !isdefined( kit.panel ) )
	{
		nacht_say( "No usable props found on this map - try another level." );
		return false;
	}

	boxes = nacht_boxes();
	plan = [];
	visuals = 0;
	solids = 0;
	foreach( box in boxes )
	{
		p = nacht_plan_box( kit, box );
		plan[ plan.size ] = p;
		visuals += p.visual_count;
		solids += p.solid_count;
	}

	used = getentarray().size;
	budget = getdvarint( "nacht_budget" );
	nacht_say( "Plan: " + boxes.size + " pieces -> " + visuals + " props + " + solids + " collision blocks (map already uses " + used + " entities, budget " + budget + ")" );
	if( visuals + solids > budget )
	{
		nacht_say( "Too many entities for this map's props. Try another level, or raise nacht_budget (risky)." );
		return false;
	}

	level.nacht_kit = kit;
	spawned = 0;
	foreach( p in plan )
	{
		ents = nacht_fill( p.box, p.visual, anchor );
		solid = nacht_fill( p.box, p.solid, anchor );
		foreach( e in solid )
			ents[ ents.size ] = e;
		if( p.box.tag != "" )
		{
			piece = spawnstruct();
			piece.box = p.box;
			piece.ents = ents;
			level.nacht_pieces[ p.box.tag ] = piece;
		}
		spawned += ents.size;
		if( spawned > 40 )
		{
			spawned = 0;
			wait 0.05;
		}
	}

	level.player setorigin( anchor + points[ "player_start" ].origin );
	level.player setplayerangles( ( 0, points[ "player_start" ].yaw, 0 ) );
	nacht_say( "Nacht built: " + level.nacht_ents.size + " entities. Walls solid: " + isdefined( kit.brushes[0] ) );
	return true;
}

nacht_clear()
{
	level notify( "nacht_end" );
	nacht_zombies_cleanup();
	foreach( ent in level.nacht_ents )
	{
		if( isdefined( ent ) )
			ent delete();
	}
	level.nacht_ents = [];
	level.nacht_pieces = [];
}

// How to cover one box: which tile (visual prop and collision block), in
// which orientation, how many of each. Nothing is spawned here.
nacht_plan_box( kit, box )
{
	dims = box.maxs - box.mins;
	thin = nacht_thin_axis( dims );

	p = spawnstruct();
	p.box = box;
	p.visual = nacht_best_tile( kit.panel_tiles[ thin ], dims, thin );
	if( box.kind == "window" && isdefined( kit.board ) )
		p.visual = nacht_best_tile( kit.board_tiles[ thin ], dims, thin );
	p.visual_count = nacht_tile_count( p.visual, dims );

	// Collision: whichever of the map's brush shapes covers it with fewest copies.
	best = undefined;
	foreach( brush in kit.brushes )
	{
		candidate = nacht_best_tile( brush.tiles[ thin ], dims, thin );
		if( !isdefined( candidate ) )
			continue;
		if( !isdefined( best ) || candidate.score < best.score )
			best = candidate;
	}
	p.solid = best;
	p.solid_count = nacht_tile_count( best, dims );
	return p;
}

nacht_thin_axis( dims )
{
	if( dims[2] <= dims[0] && dims[2] <= dims[1] )
		return 2;
	if( dims[0] <= dims[1] )
		return 0;
	return 1;
}

// Of a tile's orientations, the one that covers the box with the fewest
// copies without poking out of its ends (poking out of the thickness is fine).
nacht_best_tile( tiles, dims, thin )
{
	if( !isdefined( tiles ) )
		return undefined;
	best = undefined;
	foreach( t in tiles )
	{
		count = nacht_tile_count( t, dims );
		overhang = 0;
		for( i = 0; i < 3; i++ )
		{
			if( i != thin && t.dims[i] > dims[i] + 4 )
				overhang += t.dims[i] - dims[i];
		}
		t.score = count + overhang * 4;
		if( !isdefined( best ) || t.score < best.score )
			best = t;
	}
	return best;
}

nacht_tile_count( t, dims )
{
	if( !isdefined( t ) )
		return 0;
	n = 1;
	for( i = 0; i < 3; i++ )
		n *= nacht_steps( dims[i], t.dims[i] );
	return n;
}

nacht_steps( span, step )
{
	if( step <= 0 || span <= step )
		return 1;
	return int( ceil( span / step ) );
}

// Spawn copies of tile t so they cover the box: evenly spaced, the last one
// flush with the far edge, centred when the box is smaller than the tile.
nacht_fill( box, t, anchor )
{
	spawned = [];
	if( !isdefined( t ) )
		return spawned;
	dims = box.maxs - box.mins;
	n0 = nacht_steps( dims[0], t.dims[0] );
	n1 = nacht_steps( dims[1], t.dims[1] );
	n2 = nacht_steps( dims[2], t.dims[2] );
	for( i = 0; i < n0; i++ )
	{
		for( j = 0; j < n1; j++ )
		{
			for( k = 0; k < n2; k++ )
			{
				centre = ( nacht_slot( box.mins[0], dims[0], t.dims[0], i, n0 ),
					nacht_slot( box.mins[1], dims[1], t.dims[1], j, n1 ),
					nacht_slot( box.mins[2], dims[2], t.dims[2], k, n2 ) );
				ent = nacht_spawn_tile( t, anchor + centre );
				if( isdefined( ent ) )
				{
					level.nacht_ents[ level.nacht_ents.size ] = ent;
					spawned[ spawned.size ] = ent;
				}
			}
		}
	}
	return spawned;
}

nacht_slot( start, span, step, index, count )
{
	if( count <= 1 || span <= step )
		return start + span / 2;
	spacing = ( span - step ) / ( count - 1 );
	return start + step / 2 + spacing * index;
}

nacht_spawn_tile( t, centre )
{
	ent = spawn( "script_model", centre - t.offset );
	if( isdefined( t.brush ) )
	{
		ent clonebrushmodeltoscriptmodel( t.brush );
		ent.angles = t.angles;
		ent solid();
	}
	else
	{
		ent setmodel( t.model );
		ent.angles = t.angles;
		ent notsolid();
		ent.nacht_visual = true;
	}
	return ent;
}

// ---------------------------------------------------------------------------
// Finding props and collision on the current map

nacht_pick_kit()
{
	kit = spawnstruct();
	probe_at = level.player.origin + ( 0, 0, -8000 );

	// Collision: copies of the map's own brush models (doors, gates, crates).
	kit.brushes = [];
	brushes = getentarray( "script_brushmodel", "classname" );
	foreach( brush in brushes )
	{
		if( kit.brushes.size >= 24 )
			break;
		base = nacht_measure( undefined, brush, ( 0, 0, 0 ), probe_at );
		if( !isdefined( base ) )
			continue;
		entry = spawnstruct();
		entry.tiles = [];
		for( axis = 0; axis < 3; axis++ )
			entry.tiles[ axis ] = nacht_tile_options( base, axis, probe_at, undefined, brush );
		kit.brushes[ kit.brushes.size ] = entry;
	}

	// Looks: the map's prop models, best flat panel for walls and floors and a
	// thin plank-like one for window boards.
	names = [];
	models = getentarray( "script_model", "classname" );
	foreach( m in models )
	{
		if( isdefined( m.model ) && m.model != "" && !isdefined( names[ m.model ] ) )
			names[ m.model ] = true;
	}
	best_panel = undefined;
	best_board = undefined;
	foreach( name, unused in names )
	{
		dims = nacht_model_size( name, probe_at );
		if( !isdefined( dims ) )
			continue;
		sorted = nacht_sort3( dims );
		score = nacht_panel_score( name, sorted );
		if( score > 0 && ( !isdefined( best_panel ) || score > best_panel.score ) )
		{
			best_panel = spawnstruct();
			best_panel.name = name;
			best_panel.score = score;
		}
		board = nacht_board_score( name, sorted );
		if( board > 0 && ( !isdefined( best_board ) || board > best_board.score ) )
		{
			best_board = spawnstruct();
			best_board.name = name;
			best_board.score = board;
		}
	}

	if( isdefined( best_panel ) )
	{
		kit.panel = best_panel.name;
		kit.panel_tiles = nacht_model_tiles( kit.panel, probe_at );
	}
	if( isdefined( best_board ) && isdefined( kit.panel ) && best_board.name != kit.panel )
	{
		kit.board = best_board.name;
		kit.board_tiles = nacht_model_tiles( kit.board, probe_at );
	}

	nacht_say( "Props: walls " + nacht_str( kit.panel ) + ", boards " + nacht_str( kit.board ) + ", collision sources " + kit.brushes.size + " of " + brushes.size + " (" + names.size + " prop models on map)" );
	return kit;
}

nacht_str( value )
{
	if( !isdefined( value ) )
		return "none";
	return value;
}

nacht_model_tiles( name, probe_at )
{
	tiles = [];
	base = nacht_measure( name, undefined, ( 0, 0, 0 ), probe_at );
	for( axis = 0; axis < 3; axis++ )
		tiles[ axis ] = nacht_tile_options( base, axis, probe_at, name, undefined );
	return tiles;
}

// Orientations to try for a target thin axis: the tile's thinnest local
// axis is turned onto `axis`, plus the same rotated a quarter turn about it.
nacht_tile_options( base, axis, probe_at, model, brush )
{
	options = [];
	if( !isdefined( base ) )
		return options;
	thin = nacht_thin_axis( base.dims );
	angles = nacht_turn( thin, axis );
	options[ options.size ] = nacht_measure( model, brush, angles, probe_at );
	if( axis == 2 )
		options[ options.size ] = nacht_measure( model, brush, angles + ( 0, 90, 0 ), probe_at );
	else if( axis == 0 )
		options[ options.size ] = nacht_measure( model, brush, angles + ( 0, 0, 90 ), probe_at );
	else
		options[ options.size ] = nacht_measure( model, brush, angles + ( 90, 0, 0 ), probe_at );

	out = [];
	foreach( o in options )
	{
		if( isdefined( o ) )
			out[ out.size ] = o;
	}
	return out;
}

// Angles that turn local axis `from` onto world axis `to` (sign ignored).
nacht_turn( from, to )
{
	if( from == to )
		return ( 0, 0, 0 );
	if( ( from == 0 && to == 1 ) || ( from == 1 && to == 0 ) )
		return ( 0, 90, 0 );
	if( ( from == 0 && to == 2 ) || ( from == 2 && to == 0 ) )
		return ( 90, 0, 0 );
	return ( 0, 0, 90 );
}

// Spawn a probe with this model or brush collision at these angles and read
// its world bounding box. Returns dims, the centre's offset from the origin,
// and what to spawn later.
nacht_measure( model, brush, angles, probe_at )
{
	// Freed entity slots aren't reused straight away; don't spawn hundreds of
	// probes in a single frame.
	level.nacht_probe_count++;
	if( level.nacht_probe_count % 12 == 0 )
		wait 0.05;
	probe = spawn( "script_model", probe_at );
	probe.angles = angles;
	if( isdefined( brush ) )
		probe clonebrushmodeltoscriptmodel( brush );
	else
		probe setmodel( model );
	probe.angles = angles;
	lo = probe getpointinbounds( -1, -1, -1 );
	hi = probe getpointinbounds( 1, 1, 1 );
	probe delete();

	dims = hi - lo;
	if( dims[0] < 2 || dims[1] < 2 || dims[2] < 2 || dims[0] > 1024 || dims[1] > 1024 || dims[2] > 1024 )
		return undefined;
	t = spawnstruct();
	t.dims = dims;
	t.offset = ( lo + hi ) / 2 - probe_at;
	t.angles = angles;
	t.model = model;
	t.brush = brush;
	t.score = 0;
	return t;
}

nacht_model_size( name, probe_at )
{
	t = nacht_measure( name, undefined, ( 0, 0, 0 ), probe_at );
	if( !isdefined( t ) )
		return undefined;
	return t.dims;
}

nacht_sort3( v )
{
	a = v[0];
	b = v[1];
	c = v[2];
	if( a > b ) { tmp = a; a = b; b = tmp; }
	if( b > c ) { tmp = b; b = c; c = tmp; }
	if( a > b ) { tmp = a; a = b; b = tmp; }
	return ( a, b, c );
}

// Flat, fairly large and named like building material: good wall panel.
nacht_panel_score( name, s )
{
	if( s[0] > 32 || s[1] < 32 || s[2] < 48 )
		return 0;
	score = s[1] * s[2] / 100;
	lower = tolower( name );
	words = strtok( "wall,panel,plywood,board,wood,plank,door,sheet,concrete,brick,fence,metal", "," );
	foreach( w in words )
	{
		if( issubstr( lower, w ) )
			score += 400;
	}
	if( issubstr( lower, "glass" ) || issubstr( lower, "window" ) || issubstr( lower, "light" ) || issubstr( lower, "sign" ) )
		score = score / 4;
	return score;
}

// Long and thin: good window boards.
nacht_board_score( name, s )
{
	if( s[0] > 12 || s[1] > 24 || s[2] < 40 )
		return 0;
	score = s[2];
	lower = tolower( name );
	if( issubstr( lower, "plank" ) || issubstr( lower, "board" ) || issubstr( lower, "wood" ) )
		score += 400;
	return score;
}

// ---------------------------------------------------------------------------
// Zombies mode
//
// MW2CR has no zombies, so the level's own enemy soldiers stand in for them:
// they're told to ignore everything and come at you, hit only in melee range,
// and climb in through Nacht's windows after tearing the boards off.

nacht_zombies_start()
{
	level endon( "nacht_end" );

	level.nacht_round = 0;
	level.nacht_points = 500;
	level.nacht_double = false;
	level.nacht_insta = false;
	level.nacht_zombies = [];
	level.nacht_extra_ents = [];
	level.nacht_bought = [];

	nacht_collect_weapons();
	nacht_clear_level_ai();
	if( level.nacht_spawners.size == 0 )
	{
		nacht_say( "This level has no soldier spawners to turn into zombies - try another level." );
		return;
	}

	nacht_setup_player();
	nacht_hud_create();
	nacht_setup_windows();
	nacht_setup_buys();
	level thread nacht_player_loop();
	level thread nacht_player_death_watch();

	nacht_say( "Zombies: " + level.nacht_spawners.size + " spawners, " + level.nacht_pool.size + " weapons, " + level.nacht_windows.size + " windows." );
	wait 3;

	for( ;; )
	{
		level.nacht_round++;
		level.nacht_hud_round setvalue( level.nacht_round );
		iprintlnbold( "Round " + level.nacht_round );
		nacht_round_run( level.nacht_round );
		wait 8;
	}
}

nacht_zombies_cleanup()
{
	if( isdefined( level.nacht_zombies ) )
	{
		foreach( z in level.nacht_zombies )
		{
			if( isdefined( z ) )
				z delete();
		}
	}
	if( isdefined( level.nacht_extra_ents ) )
	{
		foreach( e in level.nacht_extra_ents )
		{
			if( isdefined( e ) )
				e delete();
		}
	}
	if( isdefined( level.nacht_huds ) )
	{
		foreach( h in level.nacht_huds )
			h destroy();
	}
	level.nacht_zombies = [];
	level.nacht_extra_ents = [];
	level.nacht_huds = [];
}

nacht_extra( ent )
{
	level.nacht_extra_ents[ level.nacht_extra_ents.size ] = ent;
	return ent;
}

// --- Rounds -----------------------------------------------------------------

nacht_round_total( r )
{
	if( r == 1 )
		return 6;
	if( r == 2 )
		return 8;
	if( r == 3 )
		return 13;
	if( r == 4 )
		return 18;
	return 24 + ( r - 5 ) * 4;
}

nacht_round_health( r )
{
	if( r < 10 )
		return 150 + 100 * ( r - 1 );
	health = 950;
	for( i = 9; i < r; i++ )
		health = int( health * 1.1 );
	return health;
}

nacht_round_run( r )
{
	total = nacht_round_total( r );
	health = nacht_round_health( r );
	delay = 2.0 - r * 0.1;
	if( delay < 0.5 )
		delay = 0.5;

	spawned = 0;
	while( spawned < total )
	{
		if( nacht_alive_count() < 24 )
		{
			z = nacht_spawn_zombie( health );
			if( isdefined( z ) )
				spawned++;
		}
		wait delay;
	}
	while( nacht_alive_count() > 0 )
		wait 0.5;
}

nacht_alive_count()
{
	alive = [];
	foreach( z in level.nacht_zombies )
	{
		if( isdefined( z ) && isalive( z ) )
			alive[ alive.size ] = z;
	}
	level.nacht_zombies = alive;
	return alive.size;
}

// --- Zombies ------------------------------------------------------------------

// The level's weapons: whatever the player and the level's soldiers carry and
// any weapon pickups lying around. Only these are guaranteed to be loaded.
nacht_collect_weapons()
{
	names = [];
	foreach( w in level.player getweaponslistprimaries() )
		names[ w ] = true;
	foreach( ai in getaiarray() )
	{
		if( isdefined( ai.weapon ) && ai.weapon != "none" && ai.weapon != "" )
			names[ ai.weapon ] = true;
	}
	foreach( ent in getentarray() )
	{
		if( isdefined( ent.classname ) && getsubstr( ent.classname, 0, 7 ) == "weapon_" )
			names[ getsubstr( ent.classname, 7 ) ] = true;
	}

	level.nacht_pool = [];
	foreach( name, unused in names )
	{
		if( weaponinventorytype( name ) != "primary" )
			continue;
		level.nacht_pool[ level.nacht_pool.size ] = name;
	}
	print( "[nacht] weapons on this level: " + level.nacht_pool.size + "\n" );
	foreach( w in level.nacht_pool )
		print( "[nacht]   " + w + " (" + weaponclass( w ) + ")\n" );
}

// Remove the level's own soldiers (keeping their spawners for zombies).
nacht_clear_level_ai()
{
	level.nacht_spawners = [];
	foreach( s in getspawnerteamarray( "axis" ) )
		level.nacht_spawners[ level.nacht_spawners.size ] = s;
	foreach( ai in getaiarray() )
		ai delete();
}

nacht_spawn_zombie( health )
{
	windows = nacht_active_windows();
	if( windows.size == 0 )
		return undefined;
	win = windows[ randomint( windows.size ) ];
	spawner = level.nacht_spawners[ randomint( level.nacht_spawners.size ) ];

	spawner.count = 1;
	if( level.nacht_switch_team )
		spawner setspawnerteam( "axis" );
	z = spawner stalingradspawn();
	if( !isdefined( z ) || !isalive( z ) )
		return undefined;
	if( level.nacht_switch_team )
		z.team = "axis";

	z forceteleport( win.outside, ( 0, win.yaw_in, 0 ) );
	z.ignoreall = true;
	z.ignoreme = true;
	z.grenadeammo = 0;
	z.dropweapon = false;
	z.goalradius = 24;
	z.health = health;
	z.maxhealth = health;
	level.nacht_zombies[ level.nacht_zombies.size ] = z;

	z thread nacht_zombie_think( win );
	z thread nacht_zombie_damage();
	z thread nacht_zombie_death();
	return z;
}

nacht_zombie_think( win )
{
	self endon( "death" );
	level endon( "nacht_end" );

	// Tear the boards off, then climb in.
	self setgoalpos( win.outside );
	while( win.boards > 0 )
	{
		wait 1.2;
		if( distance( self.origin, win.outside ) > 96 )
			self forceteleport( win.outside, ( 0, win.yaw_in, 0 ) );
		nacht_window_set( win, win.boards - 1 );
	}
	wait 0.6;
	self forceteleport( win.inside, ( 0, win.yaw_in, 0 ) );

	self setgoalentity( level.player );
	self thread nacht_zombie_attack();
	self thread nacht_zombie_unstick();
}

nacht_zombie_attack()
{
	self endon( "death" );
	level endon( "nacht_end" );
	for( ;; )
	{
		wait 0.2;
		if( !isalive( level.player ) )
			return;
		close = distance( self.origin, level.player.origin ) < 60;
		level_with = abs( self.origin[2] - level.player.origin[2] ) < 50;
		if( close && level_with )
		{
			nacht_player_hit( self );
			wait 1.0;
		}
	}
}

// Nothing in the level's path network knows about Nacht's walls, so zombies
// can get stuck. Shuffle them toward the player through open space, and if
// that fails put them back at a window (or the top of the stairs).
nacht_zombie_unstick()
{
	self endon( "death" );
	level endon( "nacht_end" );
	last = self.origin;
	still = 0;
	for( ;; )
	{
		wait 0.5;
		if( distance( self.origin, level.player.origin ) < 70 )
		{
			still = 0;
			last = self.origin;
			continue;
		}
		if( distance( self.origin, last ) < 8 )
			still += 0.5;
		else
			still = 0;
		last = self.origin;

		if( still >= 10 || abs( self.origin[2] - level.player.origin[2] ) > 90 )
		{
			if( still >= 4 )
			{
				self forceteleport( nacht_reentry_point(), self.angles );
				still = 0;
			}
		}
		else if( still >= 2 )
			self nacht_zombie_shuffle();
	}
}

nacht_zombie_shuffle()
{
	for( i = 0; i < 5; i++ )
	{
		to_player = level.player.origin - self.origin;
		to_player = ( to_player[0], to_player[1], 0 );
		if( length( to_player ) < 40 )
			return;
		step = self.origin + vectornormalize( to_player ) * 16;
		chest = ( 0, 0, 40 );
		if( !bullettracepassed( self.origin + chest, step + chest, false, self ) )
			return;
		self forceteleport( step, vectortoangles( to_player ) );
		wait 0.1;
	}
}

nacht_reentry_point()
{
	points = nacht_points();
	if( level.player.origin[2] > level.nacht_anchor[2] + 100 && isdefined( level.nacht_bought[ "stairs" ] ) )
		return level.nacht_anchor + points[ "stairs_top" ].origin;
	best = undefined;
	foreach( w in nacht_active_windows() )
	{
		if( !isdefined( best ) || distance( w.inside, level.player.origin ) < distance( best.inside, level.player.origin ) )
			best = w;
	}
	if( !isdefined( best ) )
		return level.nacht_anchor + points[ "player_start" ].origin;
	return best.inside;
}

nacht_zombie_damage()
{
	self endon( "death" );
	for( ;; )
	{
		self waittill( "damage", amount, attacker, direction, point, type, model, tag, part );
		if( !isdefined( attacker ) || attacker != level.player )
			continue;
		self.nacht_last_type = type;
		self.nacht_last_part = part;
		if( level.nacht_insta )
			self dodamage( self.health + 100, self.origin, level.player );
		if( isalive( self ) )
			nacht_add_points( 10 );
	}
}

nacht_zombie_death()
{
	self waittill( "death" );
	if( !isdefined( self ) )
		return;
	origin = self.origin;
	if( isdefined( self.nacht_last_type ) )
	{
		if( self.nacht_last_type == "MOD_MELEE" )
			nacht_add_points( 130 );
		else if( isdefined( self.nacht_last_part ) && ( self.nacht_last_part == "head" || self.nacht_last_part == "helmet" ) )
			nacht_add_points( 100 );
		else
			nacht_add_points( 60 );
	}
	if( randomint( 100 ) < 3 )
		level thread nacht_powerup_drop( origin );
}

// --- Getting hit ----------------------------------------------------------------

// No custom animation is possible without new assets, so the hit is all
// feel: damage, a jolt toward the attacker, a shake and a red flash.
nacht_player_hit( zombie )
{
	level.player dodamage( 45, zombie.origin, zombie );
	level.player viewkick( 60, zombie.origin );
	earthquake( 0.35, 0.4, level.player.origin, 120 );
	flash = level.nacht_hud_flash;
	flash.alpha = 0.45;
	flash fadeovertime( 0.5 );
	flash.alpha = 0;
}

nacht_player_death_watch()
{
	level endon( "nacht_end" );
	level.player waittill( "death" );
	iprintlnbold( "Game over - you survived " + ( level.nacht_round - 1 ) + " rounds" );
	nacht_say( "Game over on round " + level.nacht_round );
}

// --- Player, points and HUD -------------------------------------------------------

nacht_setup_player()
{
	pistol = undefined;
	foreach( w in level.nacht_pool )
	{
		if( weaponclass( w ) == "pistol" )
			pistol = w;
	}
	if( isdefined( pistol ) )
	{
		level.player takeallweapons();
		level.player giveweapon( pistol );
		level.player givemaxammo( pistol );
		level.player switchtoweapon( pistol );
	}
	level.player setnormalhealth( 1 );
}

nacht_add_points( amount )
{
	if( level.nacht_double )
		amount *= 2;
	level.nacht_points += amount;
	level.nacht_hud_points setvalue( level.nacht_points );
}

nacht_spend( cost )
{
	if( level.nacht_points < cost )
	{
		iprintln( "Not enough points (" + cost + " needed)" );
		return false;
	}
	level.nacht_points -= cost;
	level.nacht_hud_points setvalue( level.nacht_points );
	return true;
}

nacht_hud_create()
{
	level.nacht_huds = [];

	h = nacht_hud( "right", "bottom", -24, -70, 1.8 );
	h setvalue( level.nacht_points );
	level.nacht_hud_points = h;

	h = nacht_hud( "left", "bottom", 24, -40, 3.0 );
	h.color = ( 0.55, 0, 0 );
	h setvalue( 0 );
	level.nacht_hud_round = h;

	h = nacht_hud( "center", "middle", 0, 70, 1.3 );
	h settext( "" );
	level.nacht_hud_hint = h;
	level.nacht_hint_text = "";

	h = newhudelem();
	h.x = 0;
	h.y = 0;
	h.horzalign = "fullscreen";
	h.vertalign = "fullscreen";
	h setshader( "white", 640, 480 );
	h.color = ( 0.6, 0, 0 );
	h.alpha = 0;
	h.sort = 100;
	level.nacht_hud_flash = h;
	level.nacht_huds[ level.nacht_huds.size ] = h;
}

nacht_hud( align, valign, x, y, scale )
{
	h = newhudelem();
	h.alignx = align;
	h.aligny = valign;
	h.horzalign = align;
	h.vertalign = valign;
	h.x = x;
	h.y = y;
	h.fontscale = scale;
	h.hidewheninmenu = true;
	h.foreground = true;
	level.nacht_huds[ level.nacht_huds.size ] = h;
	return h;
}

nacht_hint( text )
{
	if( level.nacht_hint_text == text )
		return;
	level.nacht_hint_text = text;
	level.nacht_hud_hint settext( text );
}

// --- Windows ------------------------------------------------------------------------

nacht_setup_windows()
{
	level.nacht_windows = [];
	needs = nacht_window_needs();
	centre = ( 120, 224, 0 );
	foreach( tag, piece in level.nacht_pieces )
	{
		box = piece.box;
		if( box.kind != "window" || box.mins[2] >= 100 )
			continue;   // upstairs windows stay boarded
		mid = ( box.mins + box.maxs ) / 2;
		if( nacht_thin_axis( box.maxs - box.mins ) == 0 )
		{
			dir = ( -1, 0, 0 );
			if( mid[0] > centre[0] )
				dir = ( 1, 0, 0 );
		}
		else
		{
			dir = ( 0, -1, 0 );
			if( mid[1] > centre[1] )
				dir = ( 0, 1, 0 );
		}
		base_point = level.nacht_anchor + ( mid[0], mid[1], 0 );

		w = spawnstruct();
		w.tag = tag;
		w.needs = needs[ tag ];
		w.inside = base_point - dir * 40 + ( 0, 0, 4 );
		w.outside = nacht_ground( base_point + dir * 64 );
		angles_in = vectortoangles( dir * -1 );
		w.yaw_in = angles_in[1];
		w.visuals = [];
		foreach( e in piece.ents )
		{
			if( isdefined( e.nacht_visual ) )
				w.visuals[ w.visuals.size ] = e;
		}
		w.boards = 6;
		level.nacht_windows[ level.nacht_windows.size ] = w;
	}
}

nacht_ground( point )
{
	trace = bullettrace( point + ( 0, 0, 48 ), point - ( 0, 0, 256 ), false, undefined );
	return trace[ "position" ] + ( 0, 0, 2 );
}

nacht_active_windows()
{
	out = [];
	foreach( w in level.nacht_windows )
	{
		if( !isdefined( w.needs ) || isdefined( level.nacht_bought[ w.needs ] ) )
			out[ out.size ] = w;
	}
	return out;
}

// Show as many board pieces as there are boards left.
nacht_window_set( w, boards )
{
	if( boards < 0 )
		boards = 0;
	if( boards > 6 )
		boards = 6;
	w.boards = boards;
	shown = int( ceil( w.visuals.size * boards / 6.0 ) );
	for( i = 0; i < w.visuals.size; i++ )
	{
		if( i < shown )
			w.visuals[i] show();
		else
			w.visuals[i] hide();
	}
}

// --- Buying: wall weapons, debris, the box ---------------------------------------------

nacht_setup_buys()
{
	level.nacht_buys = [];
	points = nacht_points();
	anchor = level.nacht_anchor;

	foreach( tag in strtok( "help_door,stairs", "," ) )
	{
		piece = level.nacht_pieces[ tag ];
		if( !isdefined( piece ) )
			continue;
		b = nacht_buy( "debris", anchor + ( piece.box.mins + piece.box.maxs ) / 2, 1000, 96 );
		b.tag = tag;
	}

	slots = [];
	slots[ "wallbuy_rifle" ] = "rifle,sniper";
	slots[ "wallbuy_carbine" ] = "rifle,smg";
	slots[ "wallbuy_smg" ] = "smg,mg";
	slots[ "wallbuy_shotgun" ] = "spread,smg";
	costs = [];
	costs[ "wallbuy_rifle" ] = 200;
	costs[ "wallbuy_carbine" ] = 600;
	costs[ "wallbuy_smg" ] = 1200;
	costs[ "wallbuy_shotgun" ] = 1200;
	used = [];
	foreach( slot, classes in slots )
	{
		weapon = nacht_pick_weapon( strtok( classes, "," ), used );
		if( !isdefined( weapon ) )
			continue;
		used[ weapon ] = true;
		p = points[ slot ];
		b = nacht_buy( "weapon", anchor + p.origin, costs[ slot ], 64 );
		b.weapon = weapon;
		model = getweaponmodel( weapon );
		if( isdefined( model ) && model != "" )
		{
			m = nacht_extra( spawn( "script_model", anchor + p.origin ) );
			m setmodel( model );
			m.angles = ( 0, p.yaw + 90, 0 );
		}
	}

	p = points[ "box" ];
	b = nacht_buy( "box", anchor + p.origin + ( 0, 0, 24 ), 950, 72 );
	kit = level.nacht_kit;
	if( isdefined( kit.panel_tiles[2][0] ) )
	{
		lid = nacht_extra( spawn( "script_model", anchor + p.origin + ( 0, 0, 24 ) ) );
		lid setmodel( kit.panel );
		lid.angles = kit.panel_tiles[2][0].angles;
	}
	level.nacht_box_busy = false;
}

nacht_buy( kind, origin, cost, radius )
{
	b = spawnstruct();
	b.kind = kind;
	b.origin = origin;
	b.cost = cost;
	b.radius = radius;
	level.nacht_buys[ level.nacht_buys.size ] = b;
	return b;
}

nacht_pick_weapon( classes, used )
{
	foreach( c in classes )
	{
		foreach( w in level.nacht_pool )
		{
			if( !isdefined( used[ w ] ) && weaponclass( w ) == c )
				return w;
		}
	}
	foreach( w in level.nacht_pool )
	{
		if( !isdefined( used[ w ] ) && weaponclass( w ) != "pistol" )
			return w;
	}
	return undefined;
}

nacht_player_loop()
{
	level endon( "nacht_end" );
	level.player endon( "death" );
	held = false;
	for( ;; )
	{
		wait 0.1;
		use = level.player usebuttonpressed();
		pressed = use && !held;
		held = use;

		// Repair the nearest window while USE is held.
		w = nacht_nearest_window();
		if( isdefined( w ) && w.boards < 6 )
		{
			nacht_hint( "Hold [Use] to rebuild the barrier" );
			if( use )
			{
				nacht_window_set( w, w.boards + 1 );
				nacht_add_points( 10 );
				wait 0.4;
			}
			continue;
		}

		b = nacht_nearest_buy();
		if( !isdefined( b ) )
		{
			nacht_hint( "" );
			continue;
		}
		nacht_hint( nacht_buy_text( b ) );
		if( pressed )
			nacht_use_buy( b );
	}
}

nacht_nearest_window()
{
	best = undefined;
	foreach( w in level.nacht_windows )
	{
		d = distance( w.inside, level.player.origin );
		if( d < 64 && ( !isdefined( best ) || d < distance( best.inside, level.player.origin ) ) )
			best = w;
	}
	return best;
}

nacht_nearest_buy()
{
	best = undefined;
	foreach( b in level.nacht_buys )
	{
		if( b.kind == "debris" && isdefined( level.nacht_bought[ b.tag ] ) )
			continue;
		d = distance( b.origin, level.player.origin );
		if( d < b.radius && ( !isdefined( best ) || d < distance( best.origin, level.player.origin ) ) )
			best = b;
	}
	return best;
}

nacht_buy_text( b )
{
	if( b.kind == "debris" )
		return "Press [Use] to clear the debris [" + b.cost + "]";
	if( b.kind == "box" )
	{
		if( isdefined( level.nacht_box_offer ) )
			return "Press [Use] to take the weapon";
		if( level.nacht_box_busy )
			return "";
		return "Press [Use] for a random weapon [" + b.cost + "]";
	}
	if( level.player hasweapon( b.weapon ) )
		return "Press [Use] for ammo [" + int( b.cost / 2 ) + "]";
	return "Press [Use] to buy " + b.weapon + " [" + b.cost + "]";
}

nacht_use_buy( b )
{
	if( b.kind == "debris" )
	{
		if( !nacht_spend( b.cost ) )
			return;
		level.nacht_bought[ b.tag ] = true;
		foreach( e in level.nacht_pieces[ b.tag ].ents )
		{
			if( isdefined( e ) )
				e delete();
		}
		return;
	}
	if( b.kind == "box" )
	{
		if( isdefined( level.nacht_box_offer ) )
		{
			nacht_give_weapon( level.nacht_box_offer );
			level.nacht_box_offer = undefined;
			return;
		}
		if( !level.nacht_box_busy && nacht_spend( b.cost ) )
			level thread nacht_box_spin( b );
		return;
	}
	if( level.player hasweapon( b.weapon ) )
	{
		if( nacht_spend( int( b.cost / 2 ) ) )
			level.player givemaxammo( b.weapon );
		return;
	}
	if( nacht_spend( b.cost ) )
		nacht_give_weapon( b.weapon );
}

nacht_give_weapon( weapon )
{
	if( level.player hasweapon( weapon ) )
	{
		level.player givemaxammo( weapon );
		return;
	}
	primaries = level.player getweaponslistprimaries();
	if( primaries.size >= 2 )
		level.player takeweapon( level.player getcurrentweapon() );
	level.player giveweapon( weapon );
	level.player givemaxammo( weapon );
	level.player switchtoweapon( weapon );
}

nacht_box_spin( b )
{
	level endon( "nacht_end" );
	level.nacht_box_busy = true;
	showcase = nacht_extra( spawn( "script_model", b.origin + ( 0, 0, 16 ) ) );
	choice = undefined;
	for( i = 0; i < 20; i++ )
	{
		choice = level.nacht_pool[ randomint( level.nacht_pool.size ) ];
		model = getweaponmodel( choice );
		if( isdefined( model ) && model != "" )
			showcase setmodel( model );
		showcase.origin = b.origin + ( 0, 0, 16 + i );
		wait 0.15;
	}
	// Offer it for 10 seconds; nacht_use_buy clears the offer when taken.
	level.nacht_box_offer = choice;
	for( t = 0; t < 100 && isdefined( level.nacht_box_offer ); t++ )
		wait 0.1;
	level.nacht_box_offer = undefined;
	showcase delete();
	level.nacht_box_busy = false;
}

// --- Power-ups ---------------------------------------------------------------------------

nacht_powerup_drop( origin )
{
	level endon( "nacht_end" );
	types = strtok( "Max Ammo,Double Points,Insta-Kill,Kaboom", "," );
	type = types[ randomint( types.size ) ];
	m = nacht_extra( spawn( "script_model", origin + ( 0, 0, 32 ) ) );
	weapon = level.player getcurrentweapon();
	if( !isdefined( weapon ) || weapon == "none" )
		weapon = level.nacht_pool[0];
	model = getweaponmodel( weapon );
	if( isdefined( model ) && model != "" )
		m setmodel( model );
	m rotateyaw( 3600, 25 );

	for( t = 0; t < 250; t++ )
	{
		if( distance( m.origin, level.player.origin ) < 64 )
		{
			iprintlnbold( type );
			level thread nacht_powerup_apply( type );
			break;
		}
		wait 0.1;
	}
	m delete();
}

nacht_powerup_apply( type )
{
	level endon( "nacht_end" );
	if( type == "Max Ammo" )
	{
		foreach( w in level.player getweaponslistall() )
			level.player givemaxammo( w );
	}
	else if( type == "Double Points" )
	{
		level.nacht_double = true;
		wait 30;
		level.nacht_double = false;
	}
	else if( type == "Insta-Kill" )
	{
		level.nacht_insta = true;
		wait 30;
		level.nacht_insta = false;
	}
	else
	{
		foreach( z in level.nacht_zombies )
		{
			if( isdefined( z ) && isalive( z ) )
				z dodamage( z.health + 100, z.origin, level.player );
		}
		nacht_add_points( 400 );
	}
}

// ---------------------------------------------------------------------------
// Layout (generated from layout.py)

nacht_boxes()
{
	b = [];
	b[ b.size ] = nacht_box( -416, -16, -16, 656, 464, 0, "floor", "" );
	b[ b.size ] = nacht_box( -416, -16, 0, -288, 0, 144, "wall", "" );
	b[ b.size ] = nacht_box( -288, -16, 0, -192, 0, 40, "wall", "" );
	b[ b.size ] = nacht_box( -288, -16, 112, -192, 0, 144, "wall", "" );
	b[ b.size ] = nacht_box( -288, -16, 40, -192, 0, 112, "window", "help_south" );
	b[ b.size ] = nacht_box( -192, -16, 0, 96, 0, 144, "wall", "" );
	b[ b.size ] = nacht_box( 96, -16, 0, 192, 0, 40, "wall", "" );
	b[ b.size ] = nacht_box( 96, -16, 112, 192, 0, 144, "wall", "" );
	b[ b.size ] = nacht_box( 96, -16, 40, 192, 0, 112, "window", "start_south_w" );
	b[ b.size ] = nacht_box( 192, -16, 0, 448, 0, 144, "wall", "" );
	b[ b.size ] = nacht_box( 448, -16, 0, 544, 0, 40, "wall", "" );
	b[ b.size ] = nacht_box( 448, -16, 112, 544, 0, 144, "wall", "" );
	b[ b.size ] = nacht_box( 448, -16, 40, 544, 0, 112, "window", "start_south_e" );
	b[ b.size ] = nacht_box( 544, -16, 0, 656, 0, 144, "wall", "" );
	b[ b.size ] = nacht_box( -416, 448, 0, -288, 464, 144, "wall", "" );
	b[ b.size ] = nacht_box( -288, 448, 0, -192, 464, 40, "wall", "" );
	b[ b.size ] = nacht_box( -288, 448, 112, -192, 464, 144, "wall", "" );
	b[ b.size ] = nacht_box( -288, 448, 40, -192, 464, 112, "window", "help_north" );
	b[ b.size ] = nacht_box( -192, 448, 0, 96, 464, 144, "wall", "" );
	b[ b.size ] = nacht_box( 96, 448, 0, 192, 464, 40, "wall", "" );
	b[ b.size ] = nacht_box( 96, 448, 112, 192, 464, 144, "wall", "" );
	b[ b.size ] = nacht_box( 96, 448, 40, 192, 464, 112, "window", "start_north" );
	b[ b.size ] = nacht_box( 192, 448, 0, 656, 464, 144, "wall", "" );
	b[ b.size ] = nacht_box( 640, 0, 0, 656, 176, 144, "wall", "" );
	b[ b.size ] = nacht_box( 640, 176, 0, 656, 272, 40, "wall", "" );
	b[ b.size ] = nacht_box( 640, 176, 112, 656, 272, 144, "wall", "" );
	b[ b.size ] = nacht_box( 640, 176, 40, 656, 272, 112, "window", "start_east" );
	b[ b.size ] = nacht_box( 640, 272, 0, 656, 448, 144, "wall", "" );
	b[ b.size ] = nacht_box( -416, 0, 0, -400, 176, 144, "wall", "" );
	b[ b.size ] = nacht_box( -416, 176, 0, -400, 272, 40, "wall", "" );
	b[ b.size ] = nacht_box( -416, 176, 112, -400, 272, 144, "wall", "" );
	b[ b.size ] = nacht_box( -416, 176, 40, -400, 272, 112, "window", "help_west" );
	b[ b.size ] = nacht_box( -416, 272, 0, -400, 448, 144, "wall", "" );
	b[ b.size ] = nacht_box( -16, 0, 0, 0, 176, 144, "wall", "" );
	b[ b.size ] = nacht_box( -16, 176, 112, 0, 288, 144, "wall", "" );
	b[ b.size ] = nacht_box( -16, 176, 0, 0, 288, 112, "debris", "help_door" );
	b[ b.size ] = nacht_box( -16, 288, 0, 0, 448, 144, "wall", "" );
	b[ b.size ] = nacht_box( 360, 352, 0, 640, 448, 16, "stair", "" );
	b[ b.size ] = nacht_box( 388, 352, 16, 640, 448, 32, "stair", "" );
	b[ b.size ] = nacht_box( 416, 352, 32, 640, 448, 48, "stair", "" );
	b[ b.size ] = nacht_box( 444, 352, 48, 640, 448, 64, "stair", "" );
	b[ b.size ] = nacht_box( 472, 352, 64, 640, 448, 80, "stair", "" );
	b[ b.size ] = nacht_box( 500, 352, 80, 640, 448, 96, "stair", "" );
	b[ b.size ] = nacht_box( 528, 352, 96, 640, 448, 112, "stair", "" );
	b[ b.size ] = nacht_box( 556, 352, 112, 640, 448, 128, "stair", "" );
	b[ b.size ] = nacht_box( 584, 352, 128, 640, 448, 144, "stair", "" );
	b[ b.size ] = nacht_box( 612, 352, 144, 640, 448, 160, "stair", "" );
	b[ b.size ] = nacht_box( 296, 352, 0, 360, 448, 96, "debris", "stairs" );
	b[ b.size ] = nacht_box( 360, 336, 0, 640, 352, 144, "wall", "" );
	b[ b.size ] = nacht_box( -416, -16, 144, -16, 464, 160, "floor", "" );
	b[ b.size ] = nacht_box( -16, -16, 144, 656, 352, 160, "floor", "" );
	b[ b.size ] = nacht_box( -16, 352, 144, 352, 464, 160, "floor", "" );
	b[ b.size ] = nacht_box( 352, 448, 144, 656, 464, 160, "floor", "" );
	b[ b.size ] = nacht_box( 640, 352, 144, 656, 448, 160, "floor", "" );
	b[ b.size ] = nacht_box( -16, -16, 160, 96, 0, 304, "wall", "" );
	b[ b.size ] = nacht_box( 96, -16, 160, 192, 0, 200, "wall", "" );
	b[ b.size ] = nacht_box( 96, -16, 272, 192, 0, 304, "wall", "" );
	b[ b.size ] = nacht_box( 96, -16, 200, 192, 0, 272, "window", "up_south_w" );
	b[ b.size ] = nacht_box( 192, -16, 160, 448, 0, 304, "wall", "" );
	b[ b.size ] = nacht_box( 448, -16, 160, 544, 0, 200, "wall", "" );
	b[ b.size ] = nacht_box( 448, -16, 272, 544, 0, 304, "wall", "" );
	b[ b.size ] = nacht_box( 448, -16, 200, 544, 0, 272, "window", "up_south_e" );
	b[ b.size ] = nacht_box( 544, -16, 160, 656, 0, 304, "wall", "" );
	b[ b.size ] = nacht_box( -16, 448, 160, 96, 464, 304, "wall", "" );
	b[ b.size ] = nacht_box( 96, 448, 160, 192, 464, 200, "wall", "" );
	b[ b.size ] = nacht_box( 96, 448, 272, 192, 464, 304, "wall", "" );
	b[ b.size ] = nacht_box( 96, 448, 200, 192, 464, 272, "window", "up_north" );
	b[ b.size ] = nacht_box( 192, 448, 160, 656, 464, 304, "wall", "" );
	b[ b.size ] = nacht_box( 640, 0, 160, 656, 176, 304, "wall", "" );
	b[ b.size ] = nacht_box( 640, 176, 160, 656, 272, 200, "wall", "" );
	b[ b.size ] = nacht_box( 640, 176, 272, 656, 272, 304, "wall", "" );
	b[ b.size ] = nacht_box( 640, 176, 200, 656, 272, 272, "window", "up_east" );
	b[ b.size ] = nacht_box( 640, 272, 160, 656, 448, 304, "wall", "" );
	b[ b.size ] = nacht_box( -16, 0, 160, 0, 176, 304, "wall", "" );
	b[ b.size ] = nacht_box( -16, 176, 160, 0, 272, 200, "wall", "" );
	b[ b.size ] = nacht_box( -16, 176, 272, 0, 272, 304, "wall", "" );
	b[ b.size ] = nacht_box( -16, 176, 200, 0, 272, 272, "window", "up_west" );
	b[ b.size ] = nacht_box( -16, 272, 160, 0, 448, 304, "wall", "" );
	b[ b.size ] = nacht_box( 304, 0, 160, 320, 160, 304, "wall", "" );
	b[ b.size ] = nacht_box( 304, 160, 272, 320, 256, 304, "wall", "" );
	b[ b.size ] = nacht_box( 304, 256, 160, 320, 448, 304, "wall", "" );
	b[ b.size ] = nacht_box( 352, 344, 160, 600, 352, 196, "rail", "" );
	b[ b.size ] = nacht_box( -16, -16, 304, 656, 464, 320, "floor", "" );
	return b;
}

nacht_points()
{
	p = [];
	p[ "player_start" ] = nacht_point( 320, 160, 8, 90 );
	p[ "box" ] = nacht_point( 560, 48, 0, 90 );
	p[ "wallbuy_rifle" ] = nacht_point( 320, 4, 56, 90 );
	p[ "wallbuy_carbine" ] = nacht_point( 636, 96, 56, 180 );
	p[ "wallbuy_smg" ] = nacht_point( -100, 4, 56, 90 );
	p[ "wallbuy_shotgun" ] = nacht_point( 240, 4, 216, 90 );
	p[ "stairs_top" ] = nacht_point( 626, 400, 168, 270 );
	return p;
}

nacht_window_needs()
{
	n = [];
	n[ "help_south" ] = "help_door";
	n[ "help_north" ] = "help_door";
	n[ "help_west" ] = "help_door";
	return n;
}

