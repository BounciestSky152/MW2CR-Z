// =============================================================================
//  Portal Bridge - Call of Duty: World at War adapter
//
//  Everything that differs between WaW and BO1 zombies lives in this file so
//  the core script compiles unchanged in both games. Line references are to
//  the stock Der Riese scripts (maps/_zombiemode*.gsc); Nacht, Verruckt and
//  Shi No Numa ship their own, slightly different copies.
//
//  Calls into the stock scripts go through the pb_x_* wrappers generated into
//  maps\_portal_bridge_platform.gsc, because Plutonium's loose-script loader
//  can't compile direct references into the zombiemode scripts.
// =============================================================================
#include maps\_portal_bridge_platform;

pb_game_id()
{
	return "waw";
}

pb_known_perks()
{
	perks = [];
	perks[ perks.size ] = "specialty_armorvest";     // Juggernog
	perks[ perks.size ] = "specialty_quickrevive";   // Quick Revive
	perks[ perks.size ] = "specialty_fastreload";    // Speed Cola
	perks[ perks.size ] = "specialty_rof";           // Double Tap
	return perks;
}

// level._effect keys to try, in order, for the portal ring.
pb_portal_fx_keys()
{
	keys = [];
	keys[ keys.size ] = "powerup_on";
	return keys;
}

pb_set_score( target )
{
	if( target < 0 )
		target = 0;
	diff = target - self.score;
	if( diff > 0 )
		self pb_x_add_to_player_score( diff );
	else if( diff < 0 )
		self pb_x_minus_to_player_score( 0 - diff );
}

// Mirrors what vending_trigger_think does after the perk bottle.
pb_give_perk( perk )
{
	self SetPerk( perk );

	if( perk == "specialty_armorvest" )
	{
		// Der Riese reads this var; Verruckt and Shi No Numa hardcode 160.
		health = 160;
		if( isDefined( level.zombie_vars[ "zombie_perk_juggernaut_health" ] ) )
			health = level.zombie_vars[ "zombie_perk_juggernaut_health" ];
		self.maxhealth = health;
		self.health = health;
	}

	// Nacht der Untoten has no perk script at all (and no machines).
	if( getEntArray( "zombie_vending", "targetname" ).size == 0 )
		return;
	self pb_x_perk_hud_create( perk );
	self thread pb_x_perk_think( perk );
}

pb_max_primaries()
{
	return 2;
}

// Dog rounds are checked with == against level.next_dog_round on every
// between_round_over, so a jump past it would end dog rounds for good.
// `last_unchecked_round` is the last round number that won't be checked.
// (Shi No Numa keeps its next dog round in a local variable that scripts
// can't reach, so dog rounds there stop after a jump past round 7.)
pb_after_round_skip( last_unchecked_round )
{
	if( isDefined( level.next_dog_round ) && level.next_dog_round <= last_unchecked_round )
		level.next_dog_round = last_unchecked_round + randomIntRange( 4, 6 );
}

// WaW's round_start resets round_number to 1, then round_think's first chalk
// intro waits about a second before drawing the round and several more before
// round_spawning starts (round_start_time is still 0 until then). Setting the
// round inside that window means round 1 never happens.
pb_set_start_round( target )
{
	waited = 0;
	while( !isDefined( level.chalk_hud1 ) || !isDefined( level.round_start_time ) )
	{
		wait 0.05;
		waited += 0.05;
		if( waited > 120 )
			return false;
	}
	if( level.round_start_time != 0 || level.round_number != 1 )
		return false;

	level.round_number = target;
	level.first_round = false;
	level.zombie_health = pb_health_for_round( target - 1 );
	level.zombie_move_speed = ( target - 1 ) * 8;
	if( isDefined( level.zombie_vars ) )
	{
		level.zombie_vars[ "zombie_spawn_delay" ] = pb_spawn_delay_for_round( target );
		if( isDefined( level.zombie_vars[ "rebuild_barrier_cap_per_round" ] ) )
		{
			cap = 50 * target;
			if( cap > 500 )
				cap = 500;
			level.zombie_vars[ "rebuild_barrier_cap_per_round" ] = cap;
		}
	}
	pb_after_round_skip( target );
	level thread pb_start_round_fixups( target );
	return true;
}

pb_start_round_fixups( target )
{
	while( level.round_start_time == 0 )
		wait 0.05;
	waittillframeend;

	// Der Riese and Shi No Numa add one health step when spawning starts, the
	// other two maps don't; set the final value either way.
	level.zombie_health = pb_health_for_round( target );
	pb_fix_chalk( target );
}

// For rounds 6-10 the stock chalk only redraws the second tally group, so the
// first group still shows a single stroke after a jump.
pb_fix_chalk( target )
{
	if( target < 6 || target > 10 || !isDefined( level.chalk_hud1 ) )
		return;
	level.chalk_hud1 SetShader( "hud_chalk_5", 64, 64 );
	level.chalk_hud1.alpha = 1;
	if( isDefined( level.chalk_hud2 ) )
	{
		level.chalk_hud2.horzAlign = "left";
		level.chalk_hud2.x = 64;
	}
}

// --- fallback (round 1 already under way) -----------------------------------

// WaW's spawner counts its own spawns instead of reading zombie_total, so
// zeroing zombie_total wouldn't stop it; let it finish and kill what it spawns.
pb_fallback_prepare( target )
{
	return false;
}

// Nacht drops a powerup for every kill; max out the per-round cap instead.
pb_fallback_tick()
{
	if( isDefined( level.powerup_drop_count ) && isDefined( level.zombie_vars ) && isDefined( level.zombie_vars[ "zombie_powerup_drop_max_per_round" ] ) )
		level.powerup_drop_count = level.zombie_vars[ "zombie_powerup_drop_max_per_round" ];
}

// No points and no powerup for zombies the round jump kills.
pb_mark_no_reward()
{
	self.marked_for_death = true;
}

pb_fallback_done( target )
{
	pb_fix_chalk( target );
}
