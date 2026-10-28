// Nacht der Untoten replica for Modern Warfare 2 Campaign Remastered (h2-mod).
//
// Builds Nacht's layout out of props and collision already loaded in the
// current map. Console commands (open the console with ~):
//   set nacht_build 1    build Nacht around you (you end up in the start room)
//   set nacht_clear 1    remove it again
// Everything is printed to the console as well, so send that output if
// something looks wrong.
//
// GENERATED FILE: edit mw2cr_nacht/nacht_template.gsc or layout.py, then run
// python3 mw2cr_nacht/layout.py

main()
{
	setdvarifuninitialized( "nacht_build", 0 );
	setdvarifuninitialized( "nacht_clear", 0 );
	setdvarifuninitialized( "nacht_budget", 1100 );
	level.nacht_ents = [];
	level thread nacht_watch();
}

nacht_watch()
{
	while( !isdefined( level.player ) )
		wait 0.1;
	wait 3;
	nacht_say( "Nacht replica loaded. Console: set nacht_build 1" );

	for( ;; )
	{
		if( getdvarint( "nacht_build" ) != 0 )
		{
			setdvar( "nacht_build", 0 );
			nacht_clear();
			nacht_build();
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
		level.player iprintln( text );
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
	anchor = level.player.origin - points[ "player_start" ] + ( 0, 0, 8 );
	anchor = ( int( anchor[0] ), int( anchor[1] ), int( anchor[2] ) );
	level.nacht_anchor = anchor;

	kit = nacht_pick_kit();
	if( !isdefined( kit.panel ) )
	{
		nacht_say( "No usable props found on this map - try another level." );
		return;
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
		return;
	}

	spawned = 0;
	foreach( p in plan )
	{
		spawned += nacht_fill( p.box, p.visual, anchor );
		spawned += nacht_fill( p.box, p.solid, anchor );
		if( spawned > 40 )
		{
			spawned = 0;
			wait 0.05;
		}
	}

	level.player setorigin( anchor + points[ "player_start" ] );
	level.player setplayerangles( ( 0, 90, 0 ) );
	nacht_say( "Nacht built: " + level.nacht_ents.size + " entities. Walls solid: " + isdefined( kit.brushes[0] ) );
}

nacht_clear()
{
	foreach( ent in level.nacht_ents )
	{
		if( isdefined( ent ) )
			ent delete();
	}
	level.nacht_ents = [];
}

// How to cover one box: which tile (visual prop and collision block), in
// which orientation, how many of each. Nothing is spawned here.
nacht_plan_box( kit, box )
{
	size = box.maxs - box.mins;
	thin = nacht_thin_axis( size );

	p = spawnstruct();
	p.box = box;
	p.visual = nacht_best_tile( kit.panel_tiles[ thin ], size, thin );
	if( box.kind == "window" && isdefined( kit.board ) )
		p.visual = nacht_best_tile( kit.board_tiles[ thin ], size, thin );
	p.visual_count = nacht_tile_count( p.visual, size );

	// Collision: whichever of the map's brush shapes covers it with fewest copies.
	best = undefined;
	foreach( brush in kit.brushes )
	{
		candidate = nacht_best_tile( brush.tiles[ thin ], size, thin );
		if( !isdefined( candidate ) )
			continue;
		if( !isdefined( best ) || candidate.score < best.score )
			best = candidate;
	}
	p.solid = best;
	p.solid_count = nacht_tile_count( best, size );
	return p;
}

nacht_thin_axis( size )
{
	if( size[2] <= size[0] && size[2] <= size[1] )
		return 2;
	if( size[0] <= size[1] )
		return 0;
	return 1;
}

// Of a tile's orientations, the one that covers the box with the fewest
// copies without poking out of its ends (poking out of the thickness is fine).
nacht_best_tile( tiles, size, thin )
{
	if( !isdefined( tiles ) )
		return undefined;
	best = undefined;
	foreach( t in tiles )
	{
		count = nacht_tile_count( t, size );
		overhang = 0;
		for( i = 0; i < 3; i++ )
		{
			if( i != thin && t.size[i] > size[i] + 4 )
				overhang += t.size[i] - size[i];
		}
		t.score = count + overhang * 4;
		if( !isdefined( best ) || t.score < best.score )
			best = t;
	}
	return best;
}

nacht_tile_count( t, size )
{
	if( !isdefined( t ) )
		return 0;
	n = 1;
	for( i = 0; i < 3; i++ )
		n *= nacht_steps( size[i], t.size[i] );
	return n;
}

nacht_steps( length, step )
{
	if( step <= 0 || length <= step )
		return 1;
	return int( ceil( length / step ) );
}

// Spawn copies of tile t so they cover the box: evenly spaced, the last one
// flush with the far edge, centred when the box is smaller than the tile.
nacht_fill( box, t, anchor )
{
	if( !isdefined( t ) )
		return 0;
	size = box.maxs - box.mins;
	n0 = nacht_steps( size[0], t.size[0] );
	n1 = nacht_steps( size[1], t.size[1] );
	n2 = nacht_steps( size[2], t.size[2] );
	count = 0;
	for( i = 0; i < n0; i++ )
	{
		for( j = 0; j < n1; j++ )
		{
			for( k = 0; k < n2; k++ )
			{
				centre = ( nacht_slot( box.mins[0], size[0], t.size[0], i, n0 ),
					nacht_slot( box.mins[1], size[1], t.size[1], j, n1 ),
					nacht_slot( box.mins[2], size[2], t.size[2], k, n2 ) );
				ent = nacht_spawn_tile( t, anchor + centre );
				if( isdefined( ent ) )
				{
					level.nacht_ents[ level.nacht_ents.size ] = ent;
					count++;
				}
			}
		}
	}
	return count;
}

nacht_slot( start, length, step, index, count )
{
	if( count <= 1 || length <= step )
		return start + length / 2;
	spacing = ( length - step ) / ( count - 1 );
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
		size = nacht_model_size( name, probe_at );
		if( !isdefined( size ) )
			continue;
		sorted = nacht_sort3( size );
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
	thin = nacht_thin_axis( base.size );
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
// its world bounding box. Returns size, the centre's offset from the origin,
// and what to spawn later.
nacht_measure( model, brush, angles, probe_at )
{
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

	size = hi - lo;
	if( size[0] < 2 || size[1] < 2 || size[2] < 2 || size[0] > 1024 || size[1] > 1024 || size[2] > 1024 )
		return undefined;
	t = spawnstruct();
	t.size = size;
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
	return t.size;
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
// Layout (generated from layout.py)

// @LAYOUT@
