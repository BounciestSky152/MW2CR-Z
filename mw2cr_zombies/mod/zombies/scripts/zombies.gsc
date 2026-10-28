// MW2CR Zombies for Modern Warfare 2 Campaign Remastered (h2-mod).
//
// With the mod loaded, Wolverines! (level "invasion") is a zombies mode: the
// level is emptied, you're put inside Nate's Sports Bar & Grill
// and kept there, and zombies come in endless rounds. The MW2CR ZOMBIES button
// on the campaign menu starts the level.
//
// Nothing is for sale until you place it: the BUILD MENU in the pause menu
// puts wall weapons and buyable barriers where you aim, with a live preview,
// and the config remembers them (zm_items, zm_item0, zm_item1, ...).
//
// Nate's outline comes from the level's own Nate's pieces (the walls and
// windows named nates_before_bombing / nates_after_bombing), so the fence,
// the indoor spots and everything you place stay inside the building.
//
// MW2CR has no zombie models, so the zombies are the level's own soldiers,
// told to ignore everything and rush you with a knife; they only hurt you up
// close. Everything the mod does is printed to the console with [zombies] in
// front.

main()
{
	if( getdvar( "mapname" ) != "invasion" )
		return;
	setdvarifuninitialized( "zm_off", 0 );
	setdvarifuninitialized( "zm_best", 0 );
	setdvarifuninitialized( "zm_items", 0 );
	setdvarifuninitialized( "zm_build_mode", 0 );
	if( getdvarint( "zm_off" ) != 0 )
		return;
	// The build menu's picks come in through this one.
	setdvar( "zm_cmd", "" );
	precacheshader( "white" );
	level thread zm_main();
	// Last: a knife for the zombies' hands, if the game has one loaded.
	foreach( name in strtok( "weapon_parabolic_knife weapon_knife h2_weapon_parabolic_knife weapon_commando_knife weapon_tactical_knife", " " ) )
	{
		if( !isdefined( level.zm_knife ) && assetexists( "xmodel", name ) )
		{
			precachemodel( name );
			level.zm_knife = name;
		}
	}
	// The Blender mystery box (assets/mystery_box), once it's built into the
	// mod's mod.ff as the model zm_mystery_box.
	if( assetexists( "xmodel", "zm_mystery_box" ) )
	{
		precachemodel( "zm_mystery_box" );
		level.zm_box_prop = "zm_mystery_box";
	}
}

// Where you start inside Nate's Sports Bar & Grill (found in-game).
zm_baked_nates()
{
	return "435 -4744 2318";
}

zm_main()
{
	while( !isdefined( level.player ) )
		wait 0.1;
	wait 1;

	zm_init();
	zm_collect_weapons();
	zm_find_spawners();
	level thread zm_cleaner();
	zm_free_player();

	level.zm_start = zm_parse_vec( zm_baked_nates() );

	// The level streams its world in around the player; have it load Nate's
	// and the streets around it before moving you there.
	level.player thread zm_stream_nates();
	zm_load_area_transients();
	iprintlnbold( "Loading Nate's Sports Bar & Grill..." );
	wait 3;
	zm_move_to_nates();
	zm_say( "Nate's Sports Bar & Grill at " + zm_vec_text( level.zm_start ) );
	zm_find_nates_bounds();
	level.zm_area = [];
	level.zm_area[0] = level.zm_start;
	// The fence runs from here on; it also brings you back if the level's
	// intro pulls you away (it can attach you to its opening scene).
	level thread zm_fence();
	zm_build_area();
	zm_game();
}

// ---------------------------------------------------------------------------
// Rooms: the barriers you place split Nate's into rooms. The room you start in
// is open; buying a barrier opens whatever is behind it.

// The indoor spots you can reach from the start without passing a closed
// barrier, and the rest. Worked out again whenever a barrier is placed,
// moved, removed or bought.
zm_update_rooms()
{
	area = level.zm_area;
	gates = zm_closed_barriers();
	if( gates.size == 0 || area.size == 0 )
	{
		level.zm_open = area;
		level.zm_closed = [];
		return;
	}
	reached = [];
	reached[0] = true;
	queue = [];
	queue[0] = 0;
	head = 0;
	traces = 0;
	while( head < queue.size )
	{
		a = area[ queue[ head ] ];
		head++;
		for( j = 0; j < area.size; j++ )
		{
			if( isdefined( reached[j] ) )
				continue;
			b = area[j];
			if( abs( a[2] - b[2] ) > 60 || distance( a, b ) > 260 )
				continue;
			if( zm_near_barrier( gates, b, 32 ) || zm_crosses_barrier( gates, a, b ) )
				continue;
			traces++;
			if( traces % 40 == 0 )
				wait 0.05;
			if( bullettracepassed( a + ( 0, 0, 40 ), b + ( 0, 0, 40 ), false, undefined ) )
			{
				reached[j] = true;
				queue[ queue.size ] = j;
			}
		}
	}
	open = [];
	closed = [];
	for( j = 0; j < area.size; j++ )
	{
		if( isdefined( reached[j] ) )
			open[ open.size ] = area[j];
		else
			closed[ closed.size ] = area[j];
	}
	level.zm_open = open;
	level.zm_closed = closed;
	print( "[zombies] rooms: " + open.size + " spots open, " + closed.size + " behind barriers" );
}

zm_closed_barriers()
{
	gates = [];
	foreach( item in level.zm_items )
	{
		if( item.kind == "barrier" && !item.bought )
			gates[ gates.size ] = item;
	}
	return gates;
}

// The line from a to b passes through one of the barriers (seen from above).
zm_crosses_barrier( gates, a, b )
{
	foreach( g in gates )
	{
		if( abs( g.origin[2] - b[2] ) < 80 && zm_segments_cross( a, b, g.end_a, g.end_b ) )
			return true;
	}
	return false;
}

zm_near_barrier( gates, p, dist )
{
	foreach( g in gates )
	{
		if( abs( g.origin[2] - p[2] ) < 80 && zm_seg_point_dist( g.end_a, g.end_b, p ) < dist )
			return true;
	}
	return false;
}

zm_segments_cross( a, b, c, d )
{
	return zm_side( c, d, a ) * zm_side( c, d, b ) < 0 && zm_side( a, b, c ) * zm_side( a, b, d ) < 0;
}

// Which side of the line a-b the point p is on (seen from above).
zm_side( a, b, p )
{
	return ( b[0] - a[0] ) * ( p[1] - a[1] ) - ( b[1] - a[1] ) * ( p[0] - a[0] );
}

// Distance (top-down) from point p to the segment a-b.
zm_seg_point_dist( a, b, p )
{
	abx = b[0] - a[0];
	aby = b[1] - a[1];
	len2 = abx * abx + aby * aby;
	t = 0;
	if( len2 > 0 )
		t = ( ( p[0] - a[0] ) * abx + ( p[1] - a[1] ) * aby ) / len2;
	if( t < 0 )
		t = 0;
	if( t > 1 )
		t = 1;
	return distance2d( ( a[0] + abx * t, a[1] + aby * t, 0 ), ( p[0], p[1], 0 ) );
}

// In a closed room: in a closed barrier's doorway, or nearer a closed-off spot
// (that you can see, on this side of the barriers) than any open one. Only
// once the zombies are on; while building you can walk anywhere in Nate's.
zm_in_closed_room( pos )
{
	if( !level.zm_rounds_on || level.zm_closed.size == 0 )
		return false;
	gates = zm_closed_barriers();
	if( zm_near_barrier( gates, pos, 24 ) )
		return true;
	near_d = 999999;
	foreach( p in level.zm_open )
	{
		d = distance( p, pos );
		if( d < near_d )
			near_d = d;
	}
	near_c = undefined;
	near_c_d = 999999;
	foreach( p in level.zm_closed )
	{
		d = distance( p, pos );
		if( d < near_c_d )
		{
			near_c_d = d;
			near_c = p;
		}
	}
	if( near_c_d >= near_d || zm_crosses_barrier( gates, pos, near_c ) )
		return false;
	return bullettracepassed( pos + ( 0, 0, 40 ), near_c + ( 0, 0, 40 ), false, level.player );
}

// The rooms you can be in right now.
zm_open_area()
{
	return level.zm_open;
}

// ---------------------------------------------------------------------------
// The level streams its areas in and out as you move through it: triggers
// along the way name the streamed zones (script_transient). Starting at
// Nate's skips them, so the zones named around Nate's are loaded and kept
// loaded. (Setting off the level's own triggers swapped half the diner out.)
zm_load_area_transients()
{
	sorted = [];
	foreach( ent in getentarray() )
	{
		if( !isdefined( ent.script_transient ) )
			continue;
		d = distance( ent.origin, level.zm_start );
		i = sorted.size;
		while( i > 0 && distance( sorted[ i - 1 ].origin, level.zm_start ) > d )
		{
			sorted[i] = sorted[ i - 1 ];
			i--;
		}
		sorted[i] = ent;
	}
	print( "[zombies] streamed-zone triggers: " + sorted.size + " (nearest Nate's first)" );
	names = [];
	for( i = 0; i < sorted.size; i++ )
	{
		ent = sorted[i];
		d = int( distance( ent.origin, level.zm_start ) );
		if( i < 30 )
			print( "[zombies]   '" + ent.script_transient + "' " + zm_class_text( ent ) + " at " + zm_vec_text( ent.origin ) + ", " + d + " from Nate's" );
		if( d > 3000 )
			continue;
		foreach( name in strtok( ent.script_transient, " ,;+" ) )
		{
			if( names.size < 6 && !zm_listed( names, name ) )
				names[ names.size ] = name;
		}
	}
	// The level's checkpoints (its start points) name the zones each part of
	// the mission needs: add the ones for Nate's first.
	level.zm_transients = names;
	zm_start_point_transients();
	level thread zm_keep_transients();
}

// Lists the level's start points and any zones they name; the zones of the
// ones at Nate's are loaded too. Each start point in its own thread: one the
// mod can't read stops only itself.
zm_start_point_transients()
{
	if( !isdefined( level.start_arrays ) )
	{
		print( "[zombies] no start points listed" );
		return;
	}
	if( isdefined( level.start_point ) )
		print( "[zombies] start point now: " + level.start_point );
	foreach( name in getarraykeys( level.start_arrays ) )
		level thread zm_start_point( name );
	wait 0.05;
}

zm_start_point( name )
{
	entry = level.start_arrays[ name ];
	keys = "";
	zones = "";
	foreach( key in getarraykeys( entry ) )
	{
		keys = keys + " " + key;
		if( issubstr( tolower( key ), "transient" ) && isdefined( entry[ key ] ) )
			zones = zones + " " + entry[ key ];
	}
	print( "[zombies] start point '" + name + "' (" + keys + " ) zones:" + zones );
	if( !issubstr( tolower( name ), "nate" ) )
		return;
	foreach( zone in strtok( zones, " ,;+" ) )
	{
		if( !zm_listed( level.zm_transients, zone ) )
			level.zm_transients = zm_add_first( level.zm_transients, zone );
	}
}

zm_add_first( list, name )
{
	out = [];
	out[0] = name;
	foreach( entry in list )
	{
		if( out.size < 8 )
			out[ out.size ] = entry;
	}
	return out;
}

zm_class_text( ent )
{
	if( isdefined( ent.classname ) )
		return ent.classname;
	return "entity";
}

zm_listed( list, name )
{
	foreach( entry in list )
	{
		if( entry == name )
			return true;
	}
	return false;
}

// The level drops zones as you go (its triggers inside Nate's may swap them),
// so any that went are loaded again.
zm_keep_transients()
{
	level endon( "zm_end" );
	level.zm_transient_busy = [];
	level.zm_transient_loads = [];
	for( ;; )
	{
		foreach( name in level.zm_transients )
		{
			if( !isdefined( level.zm_transient_busy[ name ] ) )
				level thread zm_load_transient( name );
		}
		wait 5;
	}
}

// Its own thread: an unknown zone only stops this thread.
zm_load_transient( name )
{
	if( istransientloaded( name ) )
		return;
	level.zm_transient_busy[ name ] = true;
	if( !isdefined( level.zm_transient_loads[ name ] ) )
		level.zm_transient_loads[ name ] = 0;
	level.zm_transient_loads[ name ]++;
	loads = level.zm_transient_loads[ name ];
	if( loads <= 3 )
		print( "[zombies] loading streamed zone " + name + " (time " + loads + ")" );
	loadtransient( name );
	wait 8;
	if( loads <= 3 )
		print( "[zombies] streamed zone " + name + " loaded: " + istransientloaded( name ) );
	level.zm_transient_busy[ name ] = undefined;
}

// ---------------------------------------------------------------------------
// Weapons that may or may not be in this level: check by name, in a thread of
// its own so an unknown name can't stop anything else.
zm_find_weapon( names )
{
	foreach( name in names )
	{
		level.zm_found_weapon = undefined;
		level thread zm_check_weapon( name );
		wait 0.05;
		if( isdefined( level.zm_found_weapon ) )
			return level.zm_found_weapon;
	}
	return undefined;
}

zm_check_weapon( name )
{
	if( assetexists( "weapon", name ) )
		level.zm_found_weapon = name;
}

// Its own thread: if the call isn't available only this thread stops.
zm_stream_nates()
{
	self playersetstreamorigin( level.zm_start );
	wait 6;
	self playerclearstreamorigin();
}

zm_move_to_nates()
{
	zm_free_player();
	level.player setorigin( level.zm_start );
	level.player setplayerangles( ( 0, 90, 0 ) );
}

zm_init()
{
	level.zm_round = 0;
	level.zm_points = 500;
	level.zm_double = false;
	level.zm_insta = false;
	level.zm_rounds_on = false;
	level.zm_placing = false;
	level.zm_box_busy = false;
	level.zm_zombies = [];
	level.zm_ents = [];
	level.zm_buys = [];
	level.zm_items = [];
	level.zm_open = [];
	level.zm_closed = [];
	level.zm_held = [];
	level.zm_pool = [];
	level.zm_pool_names = [];
	level.zm_spawn_spots = [];
	level.zm_area = [];
	level.zm_transients = [];
	level.zm_spawn_failures = 0;
	level.zm_spawned_total = 0;
	level.zm_hits = 0;
	level.zm_last_hit = 0;
}

zm_say( text )
{
	print( "[zombies] " + text );
	iprintln( text );
}

zm_vec_text( v )
{
	return int( v[0] ) + " " + int( v[1] ) + " " + int( v[2] );
}

zm_parse_vec( text )
{
	if( !isdefined( text ) || text == "" )
		return undefined;
	parts = strtok( text, " " );
	if( parts.size < 3 )
		return undefined;
	return ( int( parts[0] ), int( parts[1] ), int( parts[2] ) );
}

zm_extra( ent )
{
	level.zm_ents[ level.zm_ents.size ] = ent;
	return ent;
}

// The level may start you in a vehicle or with controls locked for its intro.
zm_free_player()
{
	if( level.player islinked() )
		level.player unlink();
	level.player freezecontrols( false );
	// Not while placing something: building keeps weapons down.
	if( !level.zm_placing )
		level.player enableweapons();
}

// ---------------------------------------------------------------------------
// Emptying the level

// Weapons the level has loaded: the player's, its soldiers', the ones lying
// around (taken away: here you buy your guns) and the usual MW2 ones it has.
// Zombies' weapons are added as they spawn.
zm_collect_weapons()
{
	foreach( w in level.player getweaponslistprimaries() )
		zm_pool_add( w );
	foreach( ai in getaiarray() )
	{
		if( isdefined( ai.weapon ) )
			zm_pool_add( ai.weapon );
	}
	removed = 0;
	foreach( ent in getentarray() )
	{
		if( isdefined( ent.classname ) && issubstr( ent.classname, "weapon_" ) && getsubstr( ent.classname, 0, 7 ) == "weapon_" )
		{
			zm_pool_add( getsubstr( ent.classname, 7 ) );
			ent delete();
			removed++;
		}
	}
	foreach( w in zm_probe_weapons( strtok( "beretta usp glock deserteagle coltanaconda beretta393 pp2000 tmp mp5 mp5k ump45 kriss p90 uzi m4_grunt m4_grenadier m16_basic scar_h fal famas fn2000 tavor masada aug ak47 m14ebr spas12 aa12 striker m1014 ranger model1887 rpd m240 sa80 mg4 cheytac barrett wa2000 m21 dragunov rpg at4 m79", " " ) ) )
		zm_pool_add( w );
	print( "[zombies] weapons: " + level.zm_pool.size + " (" + removed + " lying around taken away)" );
	foreach( w in level.zm_pool )
		print( "[zombies]   " + zm_weapon_name( w ) + " - " + w + " (" + weaponclass( w ) + ")" );
}

// The names this level has loaded, each checked in a thread of its own so an
// unknown name can't stop anything else.
zm_probe_weapons( names )
{
	level.zm_probed = [];
	foreach( name in names )
		level thread zm_probe_weapon( name );
	wait 0.05;
	return level.zm_probed;
}

zm_probe_weapon( name )
{
	if( assetexists( "weapon", name ) )
		level.zm_probed[ level.zm_probed.size ] = name;
}

zm_pool_add( weapon )
{
	if( weapon == "none" || weapon == "" || isdefined( level.zm_pool_names[ weapon ] ) )
		return;
	level.zm_pool_names[ weapon ] = true;
	// Lock-on launchers only target vehicles: useless against zombies.
	if( issubstr( weapon, "stinger" ) || issubstr( weapon, "javelin" ) )
		return;
	if( weaponinventorytype( weapon ) != "primary" )
		return;
	level.zm_pool[ level.zm_pool.size ] = weapon;
	zm_publish_weapons();
}

// The build menu's weapon list: "name=what players call it=class;...".
zm_publish_weapons()
{
	text = "";
	foreach( w in level.zm_pool )
	{
		entry = w + "=" + zm_weapon_name( w ) + "=" + weaponclass( w );
		if( text.size + entry.size > 1000 )
			break;
		if( text != "" )
			text = text + ";";
		text = text + entry;
	}
	setdvar( "zm_weapons", text );
}

// Zombies come from the level's soldier spawners, enemy ones preferred. The
// spawners have no team set, so their class names (actor_enemy_...) decide.
zm_find_spawners()
{
	enemies = [];
	others = [];
	counts = [];
	foreach( s in getspawnerarray() )
	{
		if( !isdefined( s.classname ) || !issubstr( s.classname, "actor" ) )
			continue;
		name = tolower( s.classname );
		if( issubstr( name, "hero" ) || issubstr( name, "foley" ) || issubstr( name, "dunn" ) || issubstr( name, "raptor" ) || issubstr( name, "ramirez" ) )
			continue;
		if( !isdefined( counts[ name ] ) )
			counts[ name ] = 0;
		counts[ name ]++;
		if( issubstr( name, "enemy" ) || issubstr( name, "axis" ) || ( isdefined( s.team ) && s.team == "axis" ) )
			enemies[ enemies.size ] = s;
		else
			others[ others.size ] = s;
	}
	level.zm_spawners = enemies;
	level.zm_switch_team = false;
	if( enemies.size == 0 )
	{
		level.zm_spawners = others;
		level.zm_switch_team = true;
	}
	print( "[zombies] spawners: " + enemies.size + " enemy, " + others.size + " other" );
	foreach( name, n in counts )
		print( "[zombies]   " + name + " x" + n );
}

// Keep the level empty. Enemy soldiers are removed; friendlies are hidden
// and made harmless instead, because removing them can fail the
// mission.
zm_cleaner()
{
	level endon( "zm_end" );
	for( ;; )
	{
		foreach( ai in getaiarray() )
		{
			if( isdefined( ai.zm_zombie ) )
				continue;
			if( isdefined( ai.zm_parked ) )
				continue;
			if( isdefined( ai.team ) && ai.team == "axis" )
			{
				ai delete();
				continue;
			}
			ai.zm_parked = true;
			ai.ignoreall = true;
			ai.ignoreme = true;
			ai hide();
			ai notsolid();
		}
		if( !level.player islinked() )
		{
			foreach( ent in getentarray() )
			{
				if( isdefined( ent.classname ) && issubstr( ent.classname, "script_vehicle" ) )
					ent delete();
			}
		}
		wait 1;
	}
}

// ---------------------------------------------------------------------------
// Nate's: the indoor spots, and keeping the player inside

// Nate's outline: the box around the level's Nate's walls and windows,
// grown a little. Measured in-game as a fallback.
zm_find_nates_bounds()
{
	lo = undefined;
	hi = undefined;
	pieces = 0;
	names = [];
	foreach( ent in zm_nates_pieces() )
	{
		if( !isdefined( names[ ent.targetname ] ) )
			names[ ent.targetname ] = 0;
		names[ ent.targetname ]++;
		a = ent getpointinbounds( -1, -1, -1 );
		b = ent getpointinbounds( 1, 1, 1 );
		if( !isdefined( lo ) )
		{
			lo = a;
			hi = b;
		}
		lo = ( zm_min( lo[0], a[0] ), zm_min( lo[1], a[1] ), zm_min( lo[2], a[2] ) );
		hi = ( zm_max( hi[0], b[0] ), zm_max( hi[1], b[1] ), zm_max( hi[2], b[2] ) );
		pieces++;
	}
	foreach( name, n in names )
		print( "[zombies]   Nate's piece '" + name + "' x" + n );
	// Measured in-game: used if the pieces give nothing building-sized.
	if( !isdefined( lo ) || hi[0] - lo[0] > 2000 || hi[1] - lo[1] > 2000 )
	{
		lo = ( -100, -5070, 2290 );
		hi = ( 660, -4280, 2520 );
	}
	level.zm_lo = lo - ( 24, 24, 64 );
	level.zm_hi = hi + ( 24, 24, 64 );
	print( "[zombies] Nate's outline from " + pieces + " pieces: " + zm_vec_text( level.zm_lo ) + " to " + zm_vec_text( level.zm_hi ) );
}

// The level's pieces of Nate's (named nates_..._bombing) that are actually at
// Nate's: by where each one really is, since brush pieces may all report the
// map's centre as their origin.
zm_nates_pieces()
{
	pieces = [];
	foreach( ent in getentarray() )
	{
		if( !isdefined( ent.targetname ) || !issubstr( ent.targetname, "nates_" ) || !issubstr( ent.targetname, "bombing" ) )
			continue;
		if( distance2d( ent getpointinbounds( 0, 0, 0 ), level.zm_start ) < 900 )
			pieces[ pieces.size ] = ent;
	}
	return pieces;
}

zm_min( a, b )
{
	if( a < b )
		return a;
	return b;
}

zm_max( a, b )
{
	if( a > b )
		return a;
	return b;
}

zm_in_nates_box( pos, margin )
{
	return pos[0] >= level.zm_lo[0] - margin && pos[0] <= level.zm_hi[0] + margin
		&& pos[1] >= level.zm_lo[1] - margin && pos[1] <= level.zm_hi[1] + margin
		&& pos[2] >= level.zm_lo[2] - margin && pos[2] <= level.zm_hi[2] + margin;
}

zm_has_roof( point )
{
	trace = bullettrace( point + ( 0, 0, 40 ), point + ( 0, 0, 600 ), false, undefined );
	return trace[ "fraction" ] < 1;
}

// Nate's inside is the level's path nodes inside Nate's outline with a roof
// overhead, grown from the start spot through open space (never through a
// wall). Outdoor nodes further out are where zombies appear.
zm_build_area()
{
	center = level.zm_start;
	cands = [];
	checked = 0;
	foreach( node in getallnodes() )
	{
		checked++;
		if( checked % 150 == 0 )
			wait 0.05;
		roofed = zm_has_roof( node.origin );
		if( zm_in_nates_box( node.origin, 0 ) && roofed )
			cands[ cands.size ] = node.origin;
		else if( !roofed && !zm_in_nates_box( node.origin, 150 ) && zm_in_nates_box( node.origin, 1000 ) && level.zm_spawn_spots.size < 400 )
			level.zm_spawn_spots[ level.zm_spawn_spots.size ] = node.origin;
	}

	area = [];
	area[0] = center;
	done = [];
	queue = [];
	first = undefined;
	for( j = 0; j < cands.size; j++ )
	{
		if( distance( cands[j], center ) < 250 && ( !isdefined( first ) || distance( cands[j], center ) < distance( cands[first], center ) ) )
			first = j;
	}
	if( isdefined( first ) )
	{
		done[ first ] = true;
		queue[0] = first;
	}

	head = 0;
	traces = 0;
	while( head < queue.size )
	{
		a = cands[ queue[ head ] ];
		head++;
		area[ area.size ] = a;
		for( j = 0; j < cands.size; j++ )
		{
			if( isdefined( done[j] ) )
				continue;
			b = cands[j];
			if( abs( a[2] - b[2] ) > 60 || distance( a, b ) > 220 )
				continue;
			traces++;
			if( traces % 40 == 0 )
				wait 0.05;
			if( bullettracepassed( a + ( 0, 0, 40 ), b + ( 0, 0, 40 ), false, undefined ) )
			{
				done[j] = true;
				queue[ queue.size ] = j;
			}
		}
	}
	level.zm_area = area;
	print( "[zombies] Nate's: " + area.size + " indoor spots, " + level.zm_spawn_spots.size + " zombie spawn spots outside (" + checked + " path nodes)" );
}

// Inside Nate's: within its outline and under its roof (or a step from an
// indoor spot, for doorways), and not behind a closed barrier.
zm_inside( pos )
{
	if( !zm_in_nates_box( pos, 0 ) )
		return false;
	if( zm_in_closed_room( pos ) )
		return false;
	if( zm_has_roof( pos ) )
		return true;
	foreach( p in level.zm_area )
	{
		if( abs( p[2] - pos[2] ) < 90 && distance2d( p, pos ) < 72 )
			return true;
	}
	return false;
}

// Walking out of Nate's (or past a closed barrier) puts you back where you
// just were.
zm_fence()
{
	level endon( "zm_end" );
	level.player endon( "death" );
	last_ok = level.zm_start;
	// No warning while the level's intro is still trying to move you.
	warned = gettime() + 30000;
	moved = 0;
	for( ;; )
	{
		wait 0.1;
		pos = level.player.origin;
		if( !level.player islinked() && zm_inside( pos ) )
		{
			last_ok = pos;
			continue;
		}
		// A barrier went up around where you were: back to the start.
		if( !zm_inside( last_ok ) )
			last_ok = level.zm_start;
		zm_free_player();
		level.player setorigin( last_ok );
		moved++;
		if( moved == 1 || moved % 50 == 0 )
			print( "[zombies] put back (" + moved + " times) from " + zm_vec_text( pos ) );
		if( gettime() > warned )
		{
			iprintlnbold( "You can't go that way" );
			warned = gettime() + 3000;
		}
	}
}

// ---------------------------------------------------------------------------
// The game

zm_game()
{
	level endon( "zm_end" );
	zm_setup_player();
	zm_hud_create();
	zm_load_items();
	level thread zm_player_loop();
	level thread zm_player_death_watch();
	level thread zm_hit_recovery();
	level thread zm_build_listener();
	level.player thread zm_no_health_shield();

	if( getdvarint( "zm_build_mode" ) != 0 )
	{
		zm_say( "Build mode: no zombies until you start them from the build menu" );
		iprintlnbold( "Build mode: press Esc and pick BUILD MENU to place weapons and barriers" );
		level waittill( "zm_start_rounds" );
		setdvar( "zm_build_mode", 0 );
	}
	else if( level.zm_items.size == 0 )
		iprintlnbold( "Nothing to buy yet: press Esc and pick BUILD MENU to place weapons and barriers" );
	level.zm_rounds_on = true;

	if( level.zm_spawners.size == 0 )
	{
		zm_say( "No soldier spawners found on this level - zombies can't spawn." );
		return;
	}
	if( level.zm_spawn_spots.size == 0 )
		zm_say( "No outdoor spots found around Nate's for zombies to appear - they'll appear at their spawners instead." );
	zm_say( "Zombies: " + level.zm_spawners.size + " spawners, " + level.zm_pool.size + " weapons, " + level.zm_items.size + " things placed" );
	wait 4;

	for( ;; )
	{
		level.zm_round++;
		level.zm_hud_round setvalue( level.zm_round );
		iprintlnbold( "Round " + level.zm_round );
		zm_round_run( level.zm_round );
		zm_record_best( level.zm_round );
		iprintlnbold( "Round " + level.zm_round + " survived" );
		wait 10;
	}
}

zm_record_best( round )
{
	if( round > getdvarint( "zm_best" ) )
		executecommand( "seta zm_best " + round );
}

zm_round_total( r )
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

zm_round_health( r )
{
	if( r < 10 )
		return 150 + 100 * ( r - 1 );
	health = 950;
	for( i = 9; i < r; i++ )
		health = int( health * 1.1 );
	return health;
}

zm_round_run( r )
{
	total = zm_round_total( r );
	delay = 2.0 - r * 0.1;
	if( delay < 0.5 )
		delay = 0.5;
	spawned = 0;
	while( spawned < total )
	{
		if( zm_alive_count() < 24 )
		{
			z = zm_spawn_zombie( r );
			if( isdefined( z ) )
				spawned++;
		}
		wait delay;
	}
	while( zm_alive_count() > 0 )
		wait 0.5;
}

zm_alive_count()
{
	alive = [];
	foreach( z in level.zm_zombies )
	{
		if( isdefined( z ) && isalive( z ) )
			alive[ alive.size ] = z;
	}
	level.zm_zombies = alive;
	return alive.size;
}

// ---------------------------------------------------------------------------
// Zombies

// Somewhere outside, out of the player's sight.
zm_spawn_spot()
{
	if( level.zm_spawn_spots.size == 0 )
		return undefined;
	eye = level.player.origin + ( 0, 0, 60 );
	for( i = 0; i < 12; i++ )
	{
		spot = level.zm_spawn_spots[ randomint( level.zm_spawn_spots.size ) ];
		if( distance( spot, level.player.origin ) < 600 )
			continue;
		if( !sighttracepassed( eye, spot + ( 0, 0, 48 ), false, undefined ) )
			return spot;
	}
	return level.zm_spawn_spots[ randomint( level.zm_spawn_spots.size ) ];
}

// Walkers early on; faster runners from round 3; tough, hard-hitting brutes
// from round 6.
zm_spawn_zombie( r )
{
	spawner = level.zm_spawners[ randomint( level.zm_spawners.size ) ];
	spawner.count = 1;
	if( level.zm_switch_team )
		spawner setspawnerteam( "axis" );
	z = spawner stalingradspawn();
	if( !isdefined( z ) || !isalive( z ) )
	{
		level.zm_spawn_failures++;
		if( level.zm_spawn_failures == 10 )
			zm_say( "Zombies keep failing to spawn (10 tries) from " + level.zm_spawners.size + " spawners" );
		return undefined;
	}
	level.zm_spawn_failures = 0;
	z.zm_zombie = true;
	level.zm_zombies[ level.zm_zombies.size ] = z;
	level.zm_spawned_total++;
	// Everything else runs in the zombie's own thread, so a problem with one
	// soldier can't stop the round.
	z thread zm_zombie_setup( r );
	return z;
}

zm_zombie_setup( r )
{
	self endon( "death" );
	if( level.zm_switch_team )
		self.team = "axis";

	// Get it moving toward the player first.
	spot = zm_spawn_spot();
	if( isdefined( spot ) )
		self forceteleport( spot, ( 0, randomint( 360 ), 0 ) );
	self.ignoreall = true;
	self.ignoreme = true;
	self.fixednode = false;
	self.goalradius = 32;
	self setgoalpos( level.player.origin );

	kind = "walker";
	roll = randomint( 100 );
	if( r >= 6 && roll < 10 )
		kind = "brute";
	else if( r >= 3 && roll < 10 + r * 4 )
		kind = "runner";
	health = zm_round_health( r );
	if( kind == "brute" )
		health = health * 3;
	self.zm_kind = kind;
	self.zm_hit = 45;
	if( kind == "brute" )
		self.zm_hit = 70;
	// The mod keeps each zombie's health itself and kills it when it runs
	// out: some of the level's soldiers are made invincible by its scripts.
	self.zm_hp = health;
	self.health = 100000;
	self.maxhealth = 100000;

	self thread zm_zombie_damage();
	self thread zm_zombie_death();
	self thread zm_zombie_chase();
	self thread zm_zombie_attack();
	self thread zm_zombie_look();
	if( level.zm_spawned_total <= 3 )
		self thread zm_zombie_report();
	if( isdefined( self.weapon ) )
		zm_pool_add( self.weapon );
}

// Make the soldier act less like a soldier: walk (runners run) straight at
// you, upright, without ducking, kneeling, flinching, dodging, taking cover or
// aiming, gun hidden and a knife in hand. Its own thread: a setting the game
// won't take only stops this thread.
zm_zombie_look()
{
	self endon( "death" );
	self thread zm_zombie_stand();
	self thread zm_zombie_knife();
	self.grenadeammo = 0;
	self.dropweapon = false;
	self.dontevershoot = true;
	self.baseaccuracy = 0;
	self.combatmode = "no_cover";
	self.ignoresuppression = true;
	self.disablebulletwhizbyreaction = true;
	self.disablearrivals = true;
	self.disableexits = true;
	self.nododgemove = true;
	self.flashbangimmunity = true;
	self.battlechatter = false;
	self.allowpain = false;
	self.keepclaimednode = false;
	if( self.zm_kind == "runner" )
	{
		self.walkdist = 0;
		self.moveplaybackrate = 1.2;
	}
	else
		self.walkdist = 100000;
	self hidepart( "tag_weapon_right" );
}

// Its own thread: always standing (soldiers otherwise crouch or kneel when
// they stop), and never down on one knee in its death throes.
zm_zombie_stand()
{
	self endon( "death" );
	self allowedstances( "stand" );
	self.a.disablelongdeath = true;
}

// Its own thread: the knife, if the game has one loaded (see main).
zm_zombie_knife()
{
	self endon( "death" );
	if( isdefined( level.zm_knife ) )
		self attach( level.zm_knife, "tag_inhand" );
}

// For the console: is the first zombie of the game actually closing in?
zm_zombie_report()
{
	self endon( "death" );
	start = self.origin;
	start_d = distance( self.origin, level.player.origin );
	wait 10;
	print( "[zombies] zombie (" + self.zm_kind + ") moved " + int( distance( start, self.origin ) ) + " in 10s; distance to you " + int( start_d ) + " -> " + int( distance( self.origin, level.player.origin ) ) );
}
zm_zombie_attack()
{
	self endon( "death" );
	level endon( "zm_end" );
	for( ;; )
	{
		wait 0.2;
		if( !isalive( level.player ) )
			return;
		close = distance( self.origin, level.player.origin ) < 60;
		level_with = abs( self.origin[2] - level.player.origin[2] ) < 50;
		if( close && level_with )
		{
			zm_player_hit( self );
			wait 1.0;
		}
	}
}

// Zombies walk the level's own paths, always heading for where you are right
// now (re-aimed four times a second). One that stops moving for 4 seconds
// without reaching you, or spends 12 outside without getting closer (no way
// in), climbs in somewhere out of your sight.
zm_zombie_chase()
{
	self endon( "death" );
	level endon( "zm_end" );
	best = distance( self.origin, level.player.origin );
	anchor = self.origin;
	stuck = 0;
	lost = 0;
	for( ;; )
	{
		// The level's own spawn scripts may hand a fresh soldier a scripted
		// path or an enemy: overridden every time.
		self.ignoreall = true;
		self.favoriteenemy = undefined;
		self.goalradius = 16;
		self setgoalpos( level.player.origin );
		wait 0.25;
		d = distance( self.origin, level.player.origin );
		if( d < best - 24 || zm_in_nates_box( self.origin, 0 ) )
		{
			best = d;
			lost = 0;
		}
		else
			lost += 0.25;
		if( d < 60 || distance( self.origin, anchor ) > 48 )
		{
			anchor = self.origin;
			stuck = 0;
		}
		else
			stuck += 0.25;
		if( stuck >= 4 || lost >= 12 )
		{
			spot = zm_inside_spot();
			if( isdefined( spot ) )
				self forceteleport( spot, self.angles );
			anchor = self.origin;
			best = distance( self.origin, level.player.origin );
			stuck = 0;
			lost = 0;
		}
	}
}

// An indoor spot in Nate's away from the player and out of their sight.
zm_inside_spot()
{
	open = zm_open_area();
	if( open.size == 0 )
		return undefined;
	eye = level.player.origin + ( 0, 0, 60 );
	far = open[0];
	for( i = 0; i < 16; i++ )
	{
		p = open[ randomint( open.size ) ];
		if( distance( p, level.player.origin ) > distance( far, level.player.origin ) )
			far = p;
		if( distance( p, level.player.origin ) < 250 )
			continue;
		if( !sighttracepassed( eye, p + ( 0, 0, 48 ), false, undefined ) )
			return p;
	}
	return far;
}
zm_zombie_damage()
{
	self endon( "death" );
	for( ;; )
	{
		self waittill( "damage", amount, attacker, direction, point, type, model, tag, part );
		if( !isdefined( attacker ) || attacker != level.player )
			continue;
		self.zm_last_type = type;
		self.zm_last_part = part;
		self.zm_hp -= amount;
		if( level.zm_insta )
			self.zm_hp = 0;
		if( self.zm_hp <= 0 )
		{
			// Its own thread, and tried again on the next hit if it fails.
			self thread zm_kill_zombie();
			continue;
		}
		zm_add_points( 10 );
	}
}

zm_kill_zombie()
{
	self endon( "death" );
	self.zm_hp = 0;
	self.allowdeath = true;
	self.health = 1;
	self dodamage( 100, self.origin, level.player );
	wait 0.05;
	self kill();
}
zm_zombie_death()
{
	self waittill( "death" );
	if( !isdefined( self ) )
		return;
	origin = self.origin;
	if( isdefined( self.zm_last_type ) )
	{
		if( self.zm_last_type == "MOD_MELEE" )
			zm_add_points( 130 );
		else if( isdefined( self.zm_last_part ) && ( self.zm_last_part == "head" || self.zm_last_part == "helmet" ) )
			zm_add_points( 100 );
		else
			zm_add_points( 60 );
	}
	if( randomint( 100 ) < 3 )
		level thread zm_powerup_drop( origin );
}

// Three hits and you're down; a brute's hit counts double. Each one jolts
// you toward the zombie, shakes the screen and flashes it red.
zm_player_hit( zombie )
{
	hits = 1;
	if( isdefined( zombie.zm_kind ) && zombie.zm_kind == "brute" )
		hits = 2;
	level.zm_hits += hits;
	level.zm_last_hit = gettime();

	level.player viewkick( 127, zombie.origin );
	earthquake( 0.6, 0.6, level.player.origin, 160 );
	flash = level.zm_hud_flash;
	flash.alpha = 0.7;
	flash fadeovertime( 0.8 );
	flash.alpha = 0;

	if( level.zm_hits >= 3 )
	{
		level.zm_hits = 0;
		level.player thread zm_player_down();
		return;
	}
	// A third of your health per hit, so you can see how close you are.
	level.player.health = int( level.player.maxhealth * ( 3 - level.zm_hits ) / 3 );
}

zm_player_down()
{
	self disableinvulnerability();
	self dodamage( self.health + 1000, self.origin );
	wait 0.1;
	if( isalive( self ) )
		self kill();
}

// Four seconds without being hit and you've recovered.
zm_hit_recovery()
{
	level endon( "zm_end" );
	level.player endon( "death" );
	for( ;; )
	{
		wait 0.25;
		if( level.zm_hits > 0 && gettime() - level.zm_last_hit > 4000 )
		{
			level.zm_hits = 0;
			level.player.health = level.player.maxhealth;
		}
	}
}

// Its own thread: the game's "near death" shield would otherwise let you
// survive the third hit.
zm_no_health_shield()
{
	self enablehealthshield( false );
}

zm_player_death_watch()
{
	level endon( "zm_end" );
	level.player waittill( "death" );
	best = getdvarint( "zm_best" );
	if( level.zm_round - 1 > best )
		best = level.zm_round - 1;
	iprintlnbold( "Game over - you survived " + ( level.zm_round - 1 ) + " rounds (best " + best + ")" );
	zm_record_best( level.zm_round - 1 );
}

// ---------------------------------------------------------------------------
// Player, points, HUD

zm_setup_player()
{
	// No soldier ever takes you as a target, so none of them raise a gun at
	// you; zombies come for you because the mod sends them.
	level.player.ignoreme = true;
	weapon = zm_starting_weapon();
	if( isdefined( weapon ) )
	{
		offhands = level.player getweaponslistoffhands();
		level.player takeallweapons();
		level.player giveweapon( weapon );
		level.player givemaxammo( weapon );
		foreach( o in offhands )
		{
			level.player giveweapon( o );
			level.player givemaxammo( o );
		}
		level.player switchtoweapon( weapon );
	}
	level.player setnormalhealth( 1 );
}

// The M9 (the level's own pistol); any other pistol if it isn't loaded.
zm_starting_weapon()
{
	weapon = zm_find_weapon( strtok( "beretta", " " ) );
	if( !isdefined( weapon ) )
	{
		foreach( w in level.zm_pool )
		{
			if( weaponclass( w ) == "pistol" )
				weapon = w;
		}
	}
	if( isdefined( weapon ) )
		print( "[zombies] starting pistol: " + zm_weapon_name( weapon ) + " (" + weapon + ")" );
	return weapon;
}

zm_add_points( amount )
{
	if( level.zm_double )
		amount *= 2;
	level.zm_points += amount;
	level.zm_hud_points setvalue( level.zm_points );
}

zm_spend( cost )
{
	if( level.zm_points < cost )
	{
		iprintln( "Not enough points (" + cost + " needed)" );
		return false;
	}
	level.zm_points -= cost;
	level.zm_hud_points setvalue( level.zm_points );
	return true;
}

zm_hud_create()
{
	h = zm_hud( "right", "bottom", -24, -70, 1.8 );
	h setvalue( level.zm_points );
	level.zm_hud_points = h;

	h = zm_hud( "left", "bottom", 24, -40, 3.0 );
	h.color = ( 0.55, 0, 0 );
	h setvalue( 0 );
	level.zm_hud_round = h;

	h = zm_hud( "center", "middle", 0, 70, 1.3 );
	h settext( "" );
	level.zm_hud_hint = h;
	level.zm_hint_text = "";

	h = newhudelem();
	h.x = 0;
	h.y = 0;
	h.horzalign = "fullscreen";
	h.vertalign = "fullscreen";
	h setshader( "white", 640, 480 );
	h.color = ( 0.6, 0, 0 );
	h.alpha = 0;
	h.sort = 100;
	level.zm_hud_flash = h;
}

zm_hud( align, valign, x, y, scale )
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
	return h;
}

zm_hint( text )
{
	if( level.zm_hint_text == text )
		return;
	level.zm_hint_text = text;
	level.zm_hud_hint settext( text );
}

// ---------------------------------------------------------------------------
// Things to buy: wall weapons and barriers, placed with the build menu (in the
// pause menu) and remembered in the config as zm_items and zm_item0, zm_item1,
// ... A weapon hangs on the wall you aim at or lies on the table or floor; a
// barrier is a pile of chairs across the doorway you aim through.

// The build menu's picks, sent through the zm_cmd dvar. Each runs in its own
// thread so a bad pick can't stop the menu working.
zm_build_listener()
{
	level endon( "zm_end" );
	for( ;; )
	{
		wait 0.1;
		cmd = getdvar( "zm_cmd" );
		if( cmd == "" )
			continue;
		setdvar( "zm_cmd", "" );
		print( "[zombies] build menu: " + cmd );
		args = strtok( cmd, " " );
		if( args.size == 0 )
			continue;
		what = args[0];
		if( what == "weapon" && args.size >= 3 )
			level thread zm_place( zm_new_item( "weapon", args[1], int( args[2] ) ) );
		else if( what == "box" && args.size >= 2 )
			level thread zm_place( zm_new_item( "box", undefined, int( args[1] ) ) );
		else if( what == "barrier" && args.size >= 2 )
			level thread zm_place( zm_new_item( "barrier", undefined, int( args[1] ) ) );
		else if( what == "move" )
			level thread zm_pick( true );
		else if( what == "remove" )
			level thread zm_pick( false );
		else if( what == "clear" )
			level thread zm_clear_items();
		else if( what == "start" )
			level notify( "zm_start_rounds" );
	}
}

zm_new_item( kind, weapon, cost )
{
	item = spawnstruct();
	item.kind = kind;
	item.weapon = weapon;
	item.cost = cost;
	return item;
}

zm_item_name( item )
{
	if( item.kind == "weapon" )
		return zm_weapon_name( item.weapon );
	if( item.kind == "box" )
		return "Mystery Box";
	return "Barrier";
}

zm_item_color( item )
{
	if( item.kind == "weapon" )
		return 5;
	if( item.kind == "box" )
		return 4;
	return 1;
}

// Saved as "w weapon cost x y z pitch yaw roll", "x cost x y z yaw" (the
// mystery box) or "b cost x y z yaw left right" (how far the doorway reaches
// either side).
zm_load_items()
{
	count = getdvarint( "zm_items" );
	texts = [];
	for( i = 0; i < count; i++ )
		texts[ texts.size ] = getdvar( "zm_item" + i );
	// Nothing placed in this game's config: the layout built into the mod.
	if( count == 0 )
		texts = strtok( zm_baked_items(), "|" );
	foreach( text in texts )
	{
		item = zm_parse_item( text );
		if( isdefined( item ) )
			zm_add_item( item );
	}
	print( "[zombies] placed things: " + level.zm_items.size );
	zm_print_layout();
	zm_update_rooms();
}

// The layout built into the mod, used when nothing has been placed with the
// build menu: the "[zombies] LAYOUT ..." line from the console, pasted in.
zm_baked_items()
{
	return "";
}

// Every placed thing, readably and as one LAYOUT line to build into the mod.
zm_print_layout()
{
	layout = "";
	for( i = 0; i < level.zm_items.size; i++ )
	{
		item = level.zm_items[i];
		text = zm_item_text( item );
		print( "[zombies] item " + i + ": " + zm_item_name( item ) + ", " + item.cost + " points, at " + zm_vec_text( item.origin ) + "  (" + text + ")" );
		if( layout != "" )
			layout = layout + "|";
		layout = layout + text;
	}
	print( "[zombies] LAYOUT " + layout );
}

zm_parse_item( text )
{
	parts = strtok( text, " " );
	if( parts.size >= 9 && parts[0] == "w" )
	{
		if( !isdefined( zm_find_weapon( strtok( parts[1], " " ) ) ) )
		{
			print( "[zombies] " + parts[1] + " isn't on this level; left out" );
			return undefined;
		}
		item = zm_new_item( "weapon", parts[1], int( parts[2] ) );
		item.origin = ( int( parts[3] ), int( parts[4] ), int( parts[5] ) );
		item.angles = ( int( parts[6] ), int( parts[7] ), int( parts[8] ) );
		return item;
	}
	if( parts.size >= 6 && parts[0] == "x" )
	{
		item = zm_new_item( "box", undefined, int( parts[1] ) );
		item.origin = ( int( parts[2] ), int( parts[3] ), int( parts[4] ) );
		item.yaw = int( parts[5] );
		return item;
	}
	if( parts.size >= 8 && parts[0] == "b" )
	{
		item = zm_new_item( "barrier", undefined, int( parts[1] ) );
		item.origin = ( int( parts[2] ), int( parts[3] ), int( parts[4] ) );
		item.yaw = int( parts[5] );
		item.left = int( parts[6] );
		item.right = int( parts[7] );
		return item;
	}
	return undefined;
}

zm_item_text( item )
{
	if( item.kind == "weapon" )
		return "w " + item.weapon + " " + item.cost + " " + zm_vec_text( item.origin ) + " " + zm_vec_text( item.angles );
	if( item.kind == "box" )
		return "x " + item.cost + " " + zm_vec_text( item.origin ) + " " + int( item.yaw );
	return "b " + item.cost + " " + zm_vec_text( item.origin ) + " " + int( item.yaw ) + " " + int( item.left ) + " " + int( item.right );
}

zm_save_items()
{
	for( i = 0; i < level.zm_items.size; i++ )
		executecommand( "seta zm_item" + i + " \"" + zm_item_text( level.zm_items[i] ) + "\"" );
	executecommand( "seta zm_items " + level.zm_items.size );
	zm_print_layout();
}

// Puts a placed thing in the level: its models, outlined, and where you buy it.
zm_add_item( item )
{
	if( !isdefined( item.ents ) )
		zm_item_models( item );
	zm_item_move( item );
	item.bought = false;
	at = item.origin;
	if( item.kind == "barrier" )
		at = ( item.end_a + item.end_b ) * 0.5 + ( 0, 0, 40 );
	if( item.kind == "box" )
		at = item.origin + ( 0, 0, 24 );
	b = zm_buy( item.kind, at, item.cost );
	b.weapon = item.weapon;
	b.item = item;
	item.buy = b;
	zm_item_outline( item, zm_item_color( item ) );
	level.zm_items[ level.zm_items.size ] = item;
}

zm_remove_item( item )
{
	zm_item_delete( item );
	items = [];
	foreach( other in level.zm_items )
	{
		if( other != item )
			items[ items.size ] = other;
	}
	level.zm_items = items;
	buys = [];
	foreach( b in level.zm_buys )
	{
		if( b != item.buy )
			buys[ buys.size ] = b;
	}
	level.zm_buys = buys;
	executecommand( "seta zm_item" + items.size + " \"\"" );
}

zm_clear_items()
{
	for( i = 0; i < level.zm_items.size; i++ )
	{
		zm_item_delete( level.zm_items[i] );
		executecommand( "seta zm_item" + i + " \"\"" );
	}
	level.zm_items = [];
	level.zm_buys = [];
	executecommand( "seta zm_items 0" );
	iprintlnbold( "Everything you placed is gone" );
	zm_update_rooms();
}

zm_item_models( item )
{
	item.ents = [];
	if( item.kind == "weapon" )
	{
		item.ents[0] = zm_prop( getweaponmodel( item.weapon ) );
		return;
	}
	if( item.kind == "box" )
	{
		item.ents[0] = zm_prop( zm_box_model() );
		return;
	}
	model = zm_barrier_model();
	for( i = 0; i < 7; i++ )
		item.ents[i] = zm_prop( model );
}

zm_prop( model )
{
	m = zm_extra( spawn( "script_model", level.zm_start ) );
	if( isdefined( model ) && model != "" )
		m setmodel( model );
	m notsolid();
	return m;
}

// The Blender model if mod.ff has it (see main); until then a crate or chest
// from the level, else whatever the barriers use.
zm_box_model()
{
	if( !isdefined( level.zm_box_prop_found ) )
	{
		level.zm_box_prop_found = true;
		if( !isdefined( level.zm_box_prop ) )
			level.zm_box_prop = zm_find_model( "chest,crate,footlocker,case,ammo" );
		if( !isdefined( level.zm_box_prop ) )
			level.zm_box_prop = zm_barrier_model();
		print( "[zombies] mystery box look: " + zm_find_model_text( level.zm_box_prop ) );
	}
	return level.zm_box_prop;
}

// Chairs or stools from the level if it has them as separate props, else the
// nearest thing to a pile of junk it has.
zm_barrier_model()
{
	if( !isdefined( level.zm_barrier_prop_found ) )
	{
		level.zm_barrier_prop_found = true;
		level.zm_barrier_prop = zm_find_model( "chair,stool" );
		if( !isdefined( level.zm_barrier_prop ) )
			level.zm_barrier_prop = zm_find_model( "bench,table,crate,barrel,box,pallet,trash,cart,cone,barricade,sandbag" );
		if( !isdefined( level.zm_barrier_prop ) )
			level.zm_barrier_prop = zm_find_model( "com_,furniture,me_" );
		print( "[zombies] barrier look: " + zm_find_model_text( level.zm_barrier_prop ) );
	}
	return level.zm_barrier_prop;
}

zm_item_outline( item, color )
{
	foreach( m in item.ents )
	{
		if( isdefined( m ) )
			m thread zm_outline( color );
	}
}

zm_item_delete( item )
{
	if( !isdefined( item.ents ) )
		return;
	foreach( m in item.ents )
	{
		if( isdefined( m ) )
			m delete();
	}
	item.ents = undefined;
}

// Sets the models where the item is. A barrier's chairs are spread across
// the doorway, a second row tipped over on top of the first.
zm_item_move( item )
{
	if( item.kind == "weapon" )
	{
		m = item.ents[0];
		m.origin = item.origin;
		m.angles = item.angles;
		return;
	}
	if( item.kind == "box" )
	{
		m = item.ents[0];
		m.origin = item.origin;
		m.angles = ( 0, item.yaw, 0 );
		return;
	}
	right = anglestoright( ( 0, item.yaw, 0 ) );
	item.end_a = item.origin + right * item.right;
	item.end_b = item.origin - right * item.left;
	across = item.end_a - item.end_b;
	n = int( ( item.left + item.right ) / 30 ) + 1;
	if( n < 2 )
		n = 2;
	if( n > 4 )
		n = 4;
	k = 0;
	for( i = 0; i < n; i++ )
	{
		zm_piece( item.ents[k], item.end_b + across * ( ( i + 0.5 ) / n ), ( 0, item.yaw + 90 + ( i * 67 ) % 50 - 25, 0 ) );
		k++;
		if( i < n - 1 )
		{
			zm_piece( item.ents[k], item.end_b + across * ( ( i + 1.0 ) / n ) + ( 0, 0, 28 ), ( 0, item.yaw + 160 - i * 40, 75 ) );
			k++;
		}
	}
	while( k < item.ents.size )
	{
		item.ents[k] hide();
		k++;
	}
}

zm_piece( m, at, angles )
{
	m show();
	m.origin = at;
	m.angles = angles;
}

// Placing, with a live preview that follows your aim: [Fire] or [Use] places
// it, [Aim] turns it, [Melee] cancels.
zm_place( item )
{
	level notify( "zm_place_stop" );
	level endon( "zm_place_stop" );
	level endon( "zm_end" );
	zm_place_begin();
	item.origin = level.player.origin;
	item.angles = ( 0, 0, 0 );
	item.yaw = 0;
	item.left = 32;
	item.right = 32;
	zm_item_models( item );
	level.zm_preview = item;
	zm_item_outline( item, 2 );
	name = zm_item_name( item ) + " [" + item.cost + "]";
	turn = 0;
	for( ;; )
	{
		wait 0.05;
		ok = zm_aim_item( item, turn );
		zm_item_move( item );
		if( ok )
			zm_hint( "Placing " + name + ":  [Fire]/[Use] place   [Aim] turn   [Melee] cancel" );
		else
			zm_hint( "Aim at a spot inside Nate's   [Melee] cancels" );
		input = zm_place_input();
		if( input == "place" && ok )
			break;
		if( input == "turn" )
			turn += 15;
		if( input == "cancel" )
		{
			zm_item_delete( item );
			level.zm_preview = undefined;
			zm_place_end();
			return;
		}
	}
	level.zm_preview = undefined;
	zm_add_item( item );
	zm_save_items();
	zm_place_end();
	iprintlnbold( name + " placed" );
	zm_update_rooms();
}

// Picking a placed thing by aiming at it (it lights up): [Fire] or [Use]
// takes it, [Melee] stops. Moving puts it straight back into placing.
zm_pick( move )
{
	level notify( "zm_place_stop" );
	level endon( "zm_place_stop" );
	level endon( "zm_end" );
	zm_place_begin();
	verb = "remove";
	if( move )
		verb = "move";
	item = undefined;
	for( ;; )
	{
		wait 0.05;
		if( level.zm_items.size == 0 )
		{
			iprintlnbold( "Nothing placed yet" );
			zm_place_end();
			return;
		}
		item = zm_aimed_item();
		if( !zm_same( item, level.zm_picked ) )
		{
			zm_unpick();
			level.zm_picked = item;
			if( isdefined( item ) )
				zm_item_outline( item, 3 );
		}
		if( isdefined( item ) )
			zm_hint( "[Fire]/[Use] " + verb + " " + zm_item_name( item ) + "   [Melee] done" );
		else
			zm_hint( "Aim at something you placed to " + verb + " it   [Melee] done" );
		input = zm_place_input();
		if( input == "cancel" )
		{
			zm_unpick();
			zm_place_end();
			return;
		}
		if( input == "place" && isdefined( item ) )
			break;
	}
	level.zm_picked = undefined;
	zm_remove_item( item );
	zm_save_items();
	zm_update_rooms();
	zm_place_end();
	if( move )
		level thread zm_place( zm_new_item( item.kind, item.weapon, item.cost ) );
	else
		iprintlnbold( zm_item_name( item ) + " removed" );
}

zm_same( a, b )
{
	if( !isdefined( a ) || !isdefined( b ) )
		return !isdefined( a ) && !isdefined( b );
	return a == b;
}

zm_unpick()
{
	if( isdefined( level.zm_picked ) )
		zm_item_outline( level.zm_picked, zm_item_color( level.zm_picked ) );
	level.zm_picked = undefined;
}

zm_place_begin()
{
	// Whatever was being placed or picked before is dropped.
	if( isdefined( level.zm_preview ) )
		zm_item_delete( level.zm_preview );
	level.zm_preview = undefined;
	zm_unpick();
	level.zm_placing = true;
	level.player thread zm_weapons_off();
	// Buttons still held from the menu don't count.
	level.zm_held = [];
	zm_place_input();
}

zm_place_end()
{
	level.zm_placing = false;
	level.player thread zm_weapons_on();
	zm_hint( "" );
}

// Its own threads: if the calls aren't available only these stop.
zm_weapons_off()
{
	self disableweapons();
}

zm_weapons_on()
{
	self enableweapons();
}

// What was just pressed: "place" ([Fire] or [Use]), "turn" ([Aim]), "cancel"
// ([Melee]), or "".
zm_place_input()
{
	p = level.player;
	down = [];
	down[ "place" ] = p attackbuttonpressed() || p usebuttonpressed();
	down[ "turn" ] = p adsbuttonpressed();
	down[ "cancel" ] = p meleebuttonpressed();
	pressed = "";
	foreach( key, is_down in down )
	{
		if( is_down && !isdefined( level.zm_held[ key ] ) )
			pressed = key;
		if( is_down )
			level.zm_held[ key ] = true;
		else
			level.zm_held[ key ] = undefined;
	}
	return pressed;
}

// Where the preview goes. A weapon: on the wall you aim at, upright along it,
// or lying on the table or floor. A barrier: on the floor you aim at (below
// the wall, if you aim at one), across your line of sight and as wide as the
// doorway. False if that's not inside Nate's.
zm_aim_item( item, turn )
{
	eye = level.player geteye();
	view = level.player getplayerangles();
	trace = bullettrace( eye, eye + anglestoforward( view ) * 400, false, level.player );
	if( trace[ "fraction" ] >= 1 )
		return false;
	pos = trace[ "position" ];
	normal = trace[ "normal" ];
	if( item.kind == "weapon" )
	{
		if( normal[2] > 0.7 )
		{
			item.origin = pos + ( 0, 0, 1.5 );
			item.angles = ( 0, view[1] + 90 + turn, 90 );
		}
		else
		{
			facing = vectortoangles( normal );
			item.origin = pos + normal * 2.5;
			item.angles = ( turn, facing[1] + 90, 0 );
		}
		return zm_in_nates_box( item.origin, 24 );
	}
	ground = pos;
	if( normal[2] < 0.7 )
	{
		back = pos + normal * 16;
		down = bullettrace( back + ( 0, 0, 8 ), back - ( 0, 0, 300 ), false, level.player );
		ground = down[ "position" ];
	}
	if( item.kind == "box" )
	{
		item.yaw = view[1] + 90 + turn;
		item.origin = ground;
		return zm_in_nates_box( ground, 24 );
	}
	item.yaw = view[1] + turn;
	right = anglestoright( ( 0, item.yaw, 0 ) );
	mid = ground + ( 0, 0, 72 );
	r = bullettrace( mid, mid + right * 96, false, level.player );
	l = bullettrace( mid, mid - right * 96, false, level.player );
	item.right = r[ "fraction" ] * 96;
	item.left = l[ "fraction" ] * 96;
	item.origin = ground;
	return zm_in_nates_box( ground, 24 );
}

// The placed thing nearest your line of sight (within 40 of it, 400 away).
zm_aimed_item()
{
	eye = level.player geteye();
	dir = anglestoforward( level.player getplayerangles() );
	best = undefined;
	best_d = 40;
	foreach( item in level.zm_items )
	{
		at = item.buy.origin;
		along = vectordot( at - eye, dir );
		if( along < 0 || along > 400 )
			continue;
		d = distance( at, eye + dir * along );
		if( d < best_d )
		{
			best_d = d;
			best = item;
		}
	}
	return best;
}

zm_find_model_text( model )
{
	if( !isdefined( model ) )
		return "no prop found";
	return model;
}
// Its own thread: if outlines aren't available only this thread stops.
zm_outline( color )
{
	self hudoutlineenable( color, false );
}

zm_buy( kind, origin, cost )
{
	b = spawnstruct();
	b.kind = kind;
	b.origin = origin;
	b.cost = cost;
	level.zm_buys[ level.zm_buys.size ] = b;
	return b;
}

zm_find_model( words )
{
	list = strtok( words, "," );
	foreach( m in getentarray( "script_model", "classname" ) )
	{
		if( !isdefined( m.model ) || m.model == "" )
			continue;
		lower = tolower( m.model );
		// "box" would otherwise find the mailboxes.
		if( issubstr( lower, "mail" ) )
			continue;
		foreach( w in list )
		{
			if( issubstr( lower, w ) )
				return m.model;
		}
	}
	return undefined;
}

// The name players know a weapon by, from the start of its internal name.
zm_weapon_name( weapon )
{
	table = strtok( "beretta393=M93 Raffica|beretta=M9|scar_h=SCAR-H|ak47=AK-47|m240=M240|m14ebr=M14 EBR|cheytac=Intervention|rpg=RPG-7|m4=M4A1|fal=FAL|tavor=TAR-21|masada=ACR|famas=FAMAS|aug=AUG HBAR|mp5k=MP5K|mp5=MP5|ump45=UMP45|kriss=Vector|p90=P90|uzi=Mini-Uzi|spas12=SPAS-12|aa12=AA-12|striker=Striker|m1014=M1014|ranger=Ranger|model1887=Model 1887|barrett=Barrett .50cal|wa2000=WA2000|m21=M21 EBR|dragunov=Dragunov|sa80=L86 LSW|rpd=RPD|mg4=MG4|glock=G18|usp=USP .45|deserteagle=Desert Eagle|coltanaconda=.44 Magnum|pp2000=PP2000|tmp=TMP|at4=AT4|m79=Thumper|m16=M16A4|fn2000=F2000|g36=G36C|m249=M249 SAW|saw=M249 SAW", "|" );
	foreach( entry in table )
	{
		pair = strtok( entry, "=" );
		prefix = pair[0];
		if( weapon.size >= prefix.size && getsubstr( weapon, 0, prefix.size ) == prefix )
			return pair[1];
	}
	return weapon;
}

zm_player_loop()
{
	level endon( "zm_end" );
	level.player endon( "death" );
	held = false;
	for( ;; )
	{
		wait 0.1;
		use = level.player usebuttonpressed();
		pressed = use && !held;
		held = use;
		// While placing, [Use] places instead.
		if( level.zm_placing )
			continue;
		b = zm_nearest_buy();
		if( !isdefined( b ) )
		{
			zm_hint( "" );
			continue;
		}
		zm_hint( zm_buy_text( b ) );
		if( pressed )
			zm_use_buy( b );
	}
}

zm_nearest_buy()
{
	best = undefined;
	best_d = 96;
	at = level.player.origin + ( 0, 0, 40 );
	foreach( b in level.zm_buys )
	{
		if( b.kind == "barrier" && b.item.bought )
			continue;
		d = distance( b.origin, at );
		if( d < best_d )
		{
			best_d = d;
			best = b;
		}
	}
	return best;
}

zm_buy_text( b )
{
	if( b.kind == "barrier" )
		return "Press [Use] to clear the barrier [" + b.cost + "]";
	if( b.kind == "box" )
	{
		if( isdefined( level.zm_box_offer ) && level.zm_box_at == b )
			return "Press [Use] to take the " + zm_weapon_name( level.zm_box_offer );
		if( level.zm_box_busy )
			return "";
		return "Press [Use] for a random weapon [" + b.cost + "]";
	}
	if( level.player hasweapon( b.weapon ) )
		return "Press [Use] for ammo [" + int( b.cost / 2 ) + "]";
	return "Press [Use] to buy " + zm_weapon_name( b.weapon ) + " [" + b.cost + "]";
}

zm_use_buy( b )
{
	if( b.kind == "barrier" )
	{
		if( !b.item.bought && zm_spend( b.cost ) )
		{
			b.item.bought = true;
			foreach( m in b.item.ents )
			{
				if( isdefined( m ) )
					m hide();
			}
			iprintlnbold( "The way is clear" );
			level thread zm_update_rooms();
		}
		return;
	}
	if( b.kind == "box" )
	{
		if( isdefined( level.zm_box_offer ) && level.zm_box_at == b )
		{
			zm_give_weapon( level.zm_box_offer );
			level.zm_box_offer = undefined;
		}
		else if( !level.zm_box_busy && zm_spend( b.cost ) )
			level thread zm_box_spin( b );
		return;
	}
	if( level.player hasweapon( b.weapon ) )
	{
		if( zm_spend( int( b.cost / 2 ) ) )
			level.player givemaxammo( b.weapon );
		return;
	}
	if( zm_spend( b.cost ) )
		zm_give_weapon( b.weapon );
}

zm_give_weapon( weapon )
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

// ---------------------------------------------------------------------------
// Power-ups

zm_powerup_drop( origin )
{
	level endon( "zm_end" );
	types = strtok( "Max Ammo,Double Points,Insta-Kill,Kaboom,Bonus Points", "," );
	type = types[ randomint( types.size ) ];
	m = zm_extra( spawn( "script_model", origin + ( 0, 0, 32 ) ) );
	weapon = level.player getcurrentweapon();
	if( !isdefined( weapon ) || weapon == "none" )
		weapon = level.zm_pool[0];
	model = getweaponmodel( weapon );
	if( isdefined( model ) && model != "" )
		m setmodel( model );
	m rotateyaw( 3600, 25 );

	for( t = 0; t < 250; t++ )
	{
		if( distance( m.origin, level.player.origin ) < 64 )
		{
			iprintlnbold( type );
			level thread zm_powerup_apply( type );
			break;
		}
		wait 0.1;
	}
	m delete();
}

zm_powerup_apply( type )
{
	level endon( "zm_end" );
	if( type == "Max Ammo" )
	{
		foreach( w in level.player getweaponslistall() )
			level.player givemaxammo( w );
	}
	else if( type == "Double Points" )
	{
		level.zm_double = true;
		wait 30;
		level.zm_double = false;
	}
	else if( type == "Insta-Kill" )
	{
		level.zm_insta = true;
		wait 30;
		level.zm_insta = false;
	}
	else if( type == "Bonus Points" )
		zm_add_points( 500 );
	else
	{
		foreach( z in level.zm_zombies )
		{
			if( isdefined( z ) && isalive( z ) )
				z thread zm_kill_zombie();
		}
		zm_add_points( 400 );
	}
}

// The mystery box: weapons flick by above it for three seconds, then the one
// it lands on is yours if you take it within 10 seconds.
zm_box_spin( b )
{
	level endon( "zm_end" );
	level.zm_box_busy = true;
	level.zm_box_at = b;
	showcase = zm_extra( spawn( "script_model", b.origin ) );
	showcase notsolid();
	choice = undefined;
	for( i = 0; i < 20; i++ )
	{
		choice = level.zm_pool[ randomint( level.zm_pool.size ) ];
		model = getweaponmodel( choice );
		if( isdefined( model ) && model != "" )
			showcase setmodel( model );
		showcase.origin = b.origin + ( 0, 0, 8 + i );
		showcase.angles = ( 0, b.item.yaw, 0 );
		wait 0.15;
	}
	// zm_use_buy clears the offer when it's taken.
	level.zm_box_offer = choice;
	for( t = 0; t < 100 && isdefined( level.zm_box_offer ); t++ )
		wait 0.1;
	level.zm_box_offer = undefined;
	showcase delete();
	level.zm_box_busy = false;
}
