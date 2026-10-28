// Wolverines! Zombies for Modern Warfare 2 Campaign Remastered (h2-mod).
//
// With the mod loaded, Wolverines! (level "invasion") is a zombies mode: the
// level is emptied, you're put inside Nate's Sports Bar & Grill and kept
// there, and zombies come in endless rounds. The ZOMBIES button on the
// campaign menu starts the level.
//
// The first time, Nate's isn't known yet: walk into it and hold [Use] for 2
// seconds where you want to start. That spot is saved in your config
// (zm_nates) and printed to the console as "[zombies] NATES x y z"; put it in
// zm_baked_nates() below and nobody has to do that step again.
//
// MW2CR has no zombie models, so the zombies are the level's own soldiers,
// told to ignore everything and rush you; they only hurt you up close.
// Everything the mod does is printed to the console with [zombies] in front.

main()
{
	if( getdvar( "mapname" ) != "invasion" )
		return;
	setdvarifuninitialized( "zm_off", 0 );
	setdvarifuninitialized( "zm_nates", "" );
	setdvarifuninitialized( "zm_best", 0 );
	if( getdvarint( "zm_off" ) != 0 )
		return;
	precacheshader( "white" );
	level thread zm_main();
}

// Nate's start spot, "x y z". Empty until someone sends the NATES line.
zm_baked_nates()
{
	return "";
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
	if( !isdefined( level.zm_start ) )
		level.zm_start = zm_parse_vec( getdvar( "zm_nates" ) );
	if( !isdefined( level.zm_start ) )
		zm_first_time_setup();

	level.player setorigin( level.zm_start );
	zm_say( "Nate's Sports Bar & Grill at " + zm_vec_text( level.zm_start ) );
	zm_build_area();
	level thread zm_fence();
	zm_game();
}

zm_init()
{
	level.zm_round = 0;
	level.zm_points = 500;
	level.zm_double = false;
	level.zm_insta = false;
	level.zm_zombies = [];
	level.zm_ents = [];
	level.zm_buys = [];
	level.zm_perks = [];
	level.zm_pool = [];
	level.zm_pool_names = [];
	level.zm_spawn_spots = [];
	level.zm_area = [];
	level.zm_box_busy = false;
	level.zm_spawn_failures = 0;
}

zm_say( text )
{
	print( "[zombies] " + text + "\n" );
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
	level.player enableweapons();
}

zm_first_time_setup()
{
	zm_list_named( "nate" );
	held = 0;
	shown = 0;
	for( ;; )
	{
		if( gettime() > shown )
		{
			iprintlnbold( "First time only: walk into Nate's Sports Bar & Grill and hold [Use] for 2 seconds where you want to start" );
			shown = gettime() + 12000;
		}
		if( level.player usebuttonpressed() )
			held += 0.1;
		else
			held = 0;
		if( held >= 2 )
			break;
		wait 0.1;
	}
	level.zm_start = level.player.origin;
	executecommand( "seta zm_nates \"" + zm_vec_text( level.zm_start ) + "\"" );
	print( "[zombies] NATES " + zm_vec_text( level.zm_start ) + "\n" );
	iprintlnbold( "Saved - next time you start here" );
	wait 2;
}

// Console clues for finding Nate's automatically later.
zm_list_named( word )
{
	shown = 0;
	foreach( ent in getentarray() )
	{
		name = "";
		if( isdefined( ent.targetname ) )
			name = ent.targetname;
		if( isdefined( ent.script_noteworthy ) )
			name = name + " / " + ent.script_noteworthy;
		if( shown < 20 && issubstr( tolower( name ), word ) )
		{
			print( "[zombies] named: " + ent.classname + " " + name + " at " + zm_vec_text( ent.origin ) + "\n" );
			shown++;
		}
	}
}

// ---------------------------------------------------------------------------
// Emptying the level

// Weapons the level has loaded: the player's, its soldiers' and any pickups.
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
	foreach( ent in getentarray() )
	{
		if( isdefined( ent.classname ) && issubstr( ent.classname, "weapon_" ) && getsubstr( ent.classname, 0, 7 ) == "weapon_" )
			zm_pool_add( getsubstr( ent.classname, 7 ) );
	}
	print( "[zombies] weapons: " + level.zm_pool.size + "\n" );
	foreach( w in level.zm_pool )
		print( "[zombies]   " + w + " (" + weaponclass( w ) + ")\n" );
}

zm_pool_add( weapon )
{
	if( weapon == "none" || weapon == "" || isdefined( level.zm_pool_names[ weapon ] ) )
		return;
	level.zm_pool_names[ weapon ] = true;
	if( weaponinventorytype( weapon ) == "primary" )
		level.zm_pool[ level.zm_pool.size ] = weapon;
}

// Zombies come from the level's soldier spawners, enemy ones preferred.
zm_find_spawners()
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
	level.zm_spawners = enemies;
	level.zm_switch_team = false;
	if( enemies.size == 0 )
	{
		level.zm_spawners = others;
		level.zm_switch_team = true;
	}
	print( "[zombies] spawners: " + enemies.size + " enemy, " + others.size + " other\n" );
}

// Keep the level empty. Enemy soldiers are removed; friendlies are hidden and
// made harmless instead, because removing them can fail the mission.
zm_cleaner()
{
	level endon( "zm_end" );
	for( ;; )
	{
		foreach( ai in getaiarray() )
		{
			if( isdefined( ai.zm_zombie ) || isdefined( ai.zm_parked ) )
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

zm_has_roof( point )
{
	trace = bullettrace( point + ( 0, 0, 40 ), point + ( 0, 0, 600 ), false, undefined );
	return trace[ "fraction" ] < 1;
}

// Nate's inside is the level's path nodes with a roof overhead, grown from
// the start spot through open space (never through a wall), so the shops
// next door aren't part of it. Outdoor nodes further out are where zombies
// appear.
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
		d = distance( node.origin, center );
		roofed = zm_has_roof( node.origin );
		if( d < 1200 && roofed )
			cands[ cands.size ] = node.origin;
		if( d > 700 && d < 2400 && !roofed && level.zm_spawn_spots.size < 400 )
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
	print( "[zombies] Nate's: " + area.size + " indoor spots, " + level.zm_spawn_spots.size + " zombie spawn spots outside (" + checked + " path nodes)\n" );
}

zm_inside( pos )
{
	roofed = zm_has_roof( pos );
	foreach( p in level.zm_area )
	{
		if( abs( p[2] - pos[2] ) > 90 )
			continue;
		d = distance2d( p, pos );
		if( d < 72 || ( roofed && d < 200 ) )
			return true;
	}
	return false;
}

// Walking out of Nate's puts you back where you just were.
zm_fence()
{
	level endon( "zm_end" );
	level.player endon( "death" );
	last_ok = level.player.origin;
	warned = 0;
	for( ;; )
	{
		wait 0.1;
		pos = level.player.origin;
		if( zm_inside( pos ) )
		{
			last_ok = pos;
			continue;
		}
		level.player setorigin( last_ok );
		if( gettime() > warned )
		{
			iprintlnbold( "You can't leave Nate's" );
			warned = gettime() + 3000;
		}
	}
}

// ---------------------------------------------------------------------------
// The game

zm_game()
{
	level endon( "zm_end" );
	if( level.zm_spawners.size == 0 )
	{
		zm_say( "No soldier spawners found on this level - zombies can't spawn." );
		return;
	}
	if( level.zm_spawn_spots.size == 0 )
		zm_say( "No outdoor spots found around Nate's for zombies to appear - they'll appear at their spawners instead." );
	zm_setup_player();
	zm_hud_create();
	zm_place_buys();
	level thread zm_player_loop();
	level thread zm_player_death_watch();

	zm_say( "Zombies: " + level.zm_spawners.size + " spawners, " + level.zm_pool.size + " weapons, " + level.zm_buys.size + " things to buy" );
	iprintlnbold( "Wall weapons, perks and an ammo crate are on Nate's walls" );
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
	spot = zm_spawn_spot();
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
	if( level.zm_switch_team )
		z.team = "axis";
	if( isdefined( z.weapon ) )
		zm_pool_add( z.weapon );

	kind = "walker";
	roll = randomint( 100 );
	if( r >= 6 && roll < 10 )
		kind = "brute";
	else if( r >= 3 && roll < 10 + r * 4 )
		kind = "runner";
	health = zm_round_health( r );
	if( kind == "brute" )
		health = health * 3;
	z.zm_kind = kind;
	z.zm_hit = 45;
	if( kind == "brute" )
		z.zm_hit = 70;
	if( kind == "runner" )
		z.moveplaybackrate = 1.3;

	if( isdefined( spot ) )
		z forceteleport( spot, ( 0, randomint( 360 ), 0 ) );
	z.ignoreall = true;
	z.fixednode = false;
	z.ignoreme = true;
	z.grenadeammo = 0;
	z.dropweapon = false;
	z.goalradius = 24;
	z.health = health;
	z.maxhealth = health;
	level.zm_zombies[ level.zm_zombies.size ] = z;

	z setgoalentity( level.player );
	z thread zm_zombie_attack();
	z thread zm_zombie_unstick();
	z thread zm_zombie_damage();
	z thread zm_zombie_death();
	return z;
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

// Zombies walk the level's own paths; a long stall gets one a fresh start
// somewhere out of sight.
zm_zombie_unstick()
{
	self endon( "death" );
	level endon( "zm_end" );
	last = self.origin;
	still = 0;
	for( ;; )
	{
		wait 0.5;
		// The level's own spawn scripts may hand a fresh soldier a scripted
		// path; keep pointing it at the player.
		self.ignoreall = true;
		self setgoalentity( level.player );
		if( distance( self.origin, level.player.origin ) < 70 || distance( self.origin, last ) >= 8 )
		{
			still = 0;
			last = self.origin;
			continue;
		}
		still += 0.5;
		if( still >= 8 )
		{
			spot = zm_spawn_spot();
			if( isdefined( spot ) )
				self forceteleport( spot, self.angles );
			still = 0;
		}
	}
}

zm_zombie_damage()
{
	self endon( "death" );
	for( ;; )
	{
		self waittill( "damage", amount, attacker, direction, point, type, model, tag, part );
		if( isdefined( self.zm_own_damage ) )
		{
			self.zm_own_damage = undefined;
			continue;
		}
		if( !isdefined( attacker ) || attacker != level.player )
			continue;
		self.zm_last_type = type;
		self.zm_last_part = part;
		if( level.zm_insta )
		{
			self.zm_own_damage = true;
			self dodamage( self.health + 100, self.origin, level.player );
		}
		else if( isdefined( level.zm_perks[ "doubletap" ] ) && type != "MOD_MELEE" && isalive( self ) )
		{
			self.zm_own_damage = true;
			self dodamage( int( amount * 0.5 ) + 1, self.origin, level.player );
		}
		if( isalive( self ) )
			zm_add_points( 10 );
	}
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

// No zombie animations exist, so a hit is all feel: damage, a jolt toward
// the attacker, a shake and a red flash. Quick Revive turns a killing hit
// into a fresh start once.
zm_player_hit( zombie )
{
	damage = 45;
	if( isdefined( zombie.zm_hit ) )
		damage = zombie.zm_hit;
	level.player viewkick( 60, zombie.origin );
	earthquake( 0.35, 0.4, level.player.origin, 120 );
	flash = level.zm_hud_flash;
	flash.alpha = 0.45;
	flash fadeovertime( 0.5 );
	flash.alpha = 0;

	if( level.player.health - damage <= 0 && isdefined( level.zm_perks[ "quickrevive" ] ) )
	{
		level.zm_perks[ "quickrevive" ] = undefined;
		zm_perks_hud_update();
		level thread zm_quick_revive();
		return;
	}
	level.player dodamage( damage, zombie.origin, zombie );
}

zm_quick_revive()
{
	level.player enableinvulnerability();
	level.player.health = level.player.maxhealth;
	iprintlnbold( "Quick Revive saved you!" );
	wait 3;
	level.player disableinvulnerability();
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
	pistol = undefined;
	foreach( w in level.zm_pool )
	{
		if( weaponclass( w ) == "pistol" )
			pistol = w;
	}
	if( isdefined( pistol ) )
	{
		offhands = level.player getweaponslistoffhands();
		level.player takeallweapons();
		level.player giveweapon( pistol );
		level.player givemaxammo( pistol );
		foreach( o in offhands )
		{
			level.player giveweapon( o );
			level.player givemaxammo( o );
		}
		level.player switchtoweapon( pistol );
	}
	level.zm_base_health = level.player.maxhealth;
	level.player setnormalhealth( 1 );
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

	h = zm_hud( "right", "bottom", -24, -100, 1.1 );
	h settext( "" );
	level.zm_hud_perks = h;

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
// Things to buy: wall weapons, perks, an ammo crate, the mystery box

zm_perk_list()
{
	return strtok( "juggernog|staminup|doubletap|quickrevive", "|" );
}

zm_perk_name( perk )
{
	if( perk == "juggernog" )
		return "Juggernog";
	if( perk == "staminup" )
		return "Stamin-Up";
	if( perk == "doubletap" )
		return "Double Tap";
	return "Quick Revive";
}

zm_perk_cost( perk )
{
	if( perk == "juggernog" )
		return 2500;
	if( perk == "quickrevive" )
		return 1500;
	return 2000;
}

zm_place_buys()
{
	center = level.zm_start;
	spots = zm_spread( level.zm_area, 9 );
	slot = 0;

	// Four wall weapons.
	classes = strtok( "rifle,sniper|rifle,smg|smg,mg|spread,smg", "|" );
	costs = strtok( "200|600|1200|1200", "|" );
	used = [];
	for( i = 0; i < 4; i++ )
	{
		weapon = zm_pick_weapon( strtok( classes[i], "," ), used );
		if( !isdefined( weapon ) )
			continue;
		used[ weapon ] = true;
		wall = zm_wall_spot( zm_spot( spots, slot ) );
		slot++;
		b = zm_buy( "weapon", wall.origin, int( costs[i] ) );
		b.weapon = weapon;
		model = getweaponmodel( weapon );
		if( isdefined( model ) && model != "" )
		{
			m = zm_extra( spawn( "script_model", wall.origin ) );
			m setmodel( model );
			m.angles = ( 0, wall.yaw + 90, 0 );
		}
		print( "[zombies] wall weapon " + weapon + " at " + zm_vec_text( wall.origin ) + "\n" );
	}

	// Perks, shown with a machine-like prop from the level when there is one.
	machine = zm_find_model( "vending,soda,machine,cooler,fridge,arcade" );
	foreach( perk in zm_perk_list() )
	{
		wall = zm_wall_spot( zm_spot( spots, slot ) );
		slot++;
		b = zm_buy( "perk", wall.origin, zm_perk_cost( perk ) );
		b.perk = perk;
		if( isdefined( machine ) )
		{
			m = zm_extra( spawn( "script_model", wall.origin - ( 0, 0, 48 ) ) );
			m setmodel( machine );
			m.angles = ( 0, wall.yaw, 0 );
		}
		print( "[zombies] perk " + zm_perk_name( perk ) + " at " + zm_vec_text( wall.origin ) + "\n" );
	}

	// Ammo crate.
	wall = zm_wall_spot( zm_spot( spots, slot ) );
	zm_buy( "ammo", wall.origin, 1000 );
	crate = zm_find_model( "ammo,crate,case" );
	if( isdefined( crate ) )
	{
		m = zm_extra( spawn( "script_model", wall.origin - ( 0, 0, 48 ) ) );
		m setmodel( crate );
	}
	print( "[zombies] ammo crate at " + zm_vec_text( wall.origin ) + "\n" );

	// Mystery box near (not on) the start spot.
	box_at = center;
	foreach( p in level.zm_area )
	{
		d = distance( p, center );
		if( d > 120 && d < 600 && ( box_at == center || d < distance( box_at, center ) ) )
			box_at = p;
	}
	zm_buy( "box", box_at + ( 0, 0, 24 ), 950 );
	box = zm_find_model( "crate,box,case,chest" );
	if( isdefined( box ) )
	{
		m = zm_extra( spawn( "script_model", box_at ) );
		m setmodel( box );
	}
	print( "[zombies] mystery box at " + zm_vec_text( box_at ) + "\n" );
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

// The n-th placement spot; extra ones reuse spots, nudged so they don't overlap.
zm_spot( spots, n )
{
	if( spots.size == 0 )
		return level.zm_start;
	p = spots[ n % spots.size ];
	if( n >= spots.size )
		p = p + ( 40 * ( n / spots.size ), 0, 0 );
	return p;
}

// n points from the list, each as far as possible from the ones already picked.
zm_spread( points, n )
{
	picked = [];
	if( points.size == 0 )
		return picked;
	picked[0] = points[0];
	while( picked.size < n && picked.size < points.size )
	{
		best = undefined;
		best_d = -1;
		foreach( p in points )
		{
			nearest = 999999;
			foreach( q in picked )
			{
				d = distance( p, q );
				if( d < nearest )
					nearest = d;
			}
			if( nearest > best_d )
			{
				best_d = nearest;
				best = p;
			}
		}
		picked[ picked.size ] = best;
	}
	return picked;
}

// The closest wall to a spot, so things hang on a real wall.
zm_wall_spot( point )
{
	spot = spawnstruct();
	spot.origin = point + ( 0, 0, 48 );
	spot.yaw = 0;
	best = 97;
	for( a = 0; a < 360; a += 45 )
	{
		dir = anglestoforward( ( 0, a, 0 ) );
		start = point + ( 0, 0, 56 );
		trace = bullettrace( start, start + dir * 96, false, undefined );
		d = trace[ "fraction" ] * 96;
		if( d < best )
		{
			best = d;
			normal = trace[ "normal" ];
			spot.origin = trace[ "position" ] + normal * 3;
			facing = vectortoangles( normal );
			spot.yaw = facing[1];
		}
	}
	return spot;
}

zm_find_model( words )
{
	list = strtok( words, "," );
	foreach( m in getentarray( "script_model", "classname" ) )
	{
		if( !isdefined( m.model ) || m.model == "" )
			continue;
		lower = tolower( m.model );
		foreach( w in list )
		{
			if( issubstr( lower, w ) )
				return m.model;
		}
	}
	return undefined;
}

zm_pick_weapon( classes, used )
{
	foreach( c in classes )
	{
		foreach( w in level.zm_pool )
		{
			if( !isdefined( used[ w ] ) && weaponclass( w ) == c )
				return w;
		}
	}
	foreach( w in level.zm_pool )
	{
		if( !isdefined( used[ w ] ) && weaponclass( w ) != "pistol" )
			return w;
	}
	return undefined;
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
	foreach( b in level.zm_buys )
	{
		d = distance( b.origin, level.player.origin + ( 0, 0, 40 ) );
		if( d < 80 && ( !isdefined( best ) || d < distance( best.origin, level.player.origin + ( 0, 0, 40 ) ) ) )
			best = b;
	}
	return best;
}

zm_buy_text( b )
{
	if( b.kind == "perk" )
	{
		if( isdefined( level.zm_perks[ b.perk ] ) )
			return "You have " + zm_perk_name( b.perk );
		return "Press [Use] for " + zm_perk_name( b.perk ) + " [" + b.cost + "]";
	}
	if( b.kind == "ammo" )
		return "Press [Use] to refill all ammo and grenades [" + b.cost + "]";
	if( b.kind == "box" )
	{
		if( isdefined( level.zm_box_offer ) )
			return "Press [Use] to take the weapon";
		if( level.zm_box_busy )
			return "";
		return "Press [Use] for a random weapon [" + b.cost + "]";
	}
	if( level.player hasweapon( b.weapon ) )
		return "Press [Use] for ammo [" + int( b.cost / 2 ) + "]";
	return "Press [Use] to buy " + b.weapon + " [" + b.cost + "]";
}

zm_use_buy( b )
{
	if( b.kind == "perk" )
	{
		if( !isdefined( level.zm_perks[ b.perk ] ) && zm_spend( b.cost ) )
			zm_give_perk( b.perk );
		return;
	}
	if( b.kind == "ammo" )
	{
		if( zm_spend( b.cost ) )
		{
			foreach( w in level.player getweaponslistall() )
				level.player givemaxammo( w );
		}
		return;
	}
	if( b.kind == "box" )
	{
		if( isdefined( level.zm_box_offer ) )
		{
			zm_give_weapon( level.zm_box_offer );
			level.zm_box_offer = undefined;
			return;
		}
		if( !level.zm_box_busy && zm_spend( b.cost ) )
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

// Perks are script effects: Juggernog 2.5x health, Stamin-Up faster
// movement, Double Tap half again the damage, Quick Revive one saved death.
zm_give_perk( perk )
{
	level.zm_perks[ perk ] = true;
	if( perk == "juggernog" )
	{
		level.player.maxhealth = int( level.zm_base_health * 2.5 );
		level.player.health = level.player.maxhealth;
	}
	else if( perk == "staminup" )
		level.player setmovespeedscale( 1.15 );
	iprintlnbold( zm_perk_name( perk ) );
	zm_perks_hud_update();
}

zm_perks_hud_update()
{
	text = "";
	foreach( perk in zm_perk_list() )
	{
		if( isdefined( level.zm_perks[ perk ] ) )
			text = text + zm_perk_name( perk ) + "  ";
	}
	level.zm_hud_perks settext( text );
}

zm_box_spin( b )
{
	level endon( "zm_end" );
	level.zm_box_busy = true;
	showcase = zm_extra( spawn( "script_model", b.origin + ( 0, 0, 16 ) ) );
	choice = undefined;
	for( i = 0; i < 20; i++ )
	{
		choice = level.zm_pool[ randomint( level.zm_pool.size ) ];
		model = getweaponmodel( choice );
		if( isdefined( model ) && model != "" )
			showcase setmodel( model );
		showcase.origin = b.origin + ( 0, 0, 16 + i );
		wait 0.15;
	}
	// Offer it for 10 seconds; zm_use_buy clears the offer when taken.
	level.zm_box_offer = choice;
	for( t = 0; t < 100 && isdefined( level.zm_box_offer ); t++ )
		wait 0.1;
	level.zm_box_offer = undefined;
	showcase delete();
	level.zm_box_busy = false;
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
				z dodamage( z.health + 100, z.origin, level.player );
		}
		zm_add_points( 400 );
	}
}
