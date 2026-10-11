// =============================================================================
//  Portal Bridge - Call of Duty: Black Ops (BO1) adapter
//
//  Everything that differs between WaW and BO1 zombies lives in this file so
//  the core script compiles unchanged in both games. BO1's zombiemode scripts
//  are shared by every map (ZM/Common/maps/_zombiemode*.gsc).
//
//  Calls into the stock scripts go through the pb_x_* wrappers generated into
//  maps\_portal_bridge_platform.gsc, because Plutonium's loose-script loader
//  can't compile direct references into the zombiemode scripts.
// =============================================================================
#include maps\_portal_bridge_platform;

pb_game_id()
{
	return "bo1";
}

pb_known_perks()
{
	perks = [];
	perks[ perks.size ] = "specialty_armorvest";                // Juggernog
	perks[ perks.size ] = "specialty_quickrevive";              // Quick Revive
	perks[ perks.size ] = "specialty_fastreload";               // Speed Cola
	perks[ perks.size ] = "specialty_rof";                      // Double Tap
	perks[ perks.size ] = "specialty_longersprint";             // Stamin-Up
	perks[ perks.size ] = "specialty_flakjacket";               // PhD Flopper
	perks[ perks.size ] = "specialty_deadshot";                 // Deadshot Daiquiri
	perks[ perks.size ] = "specialty_additionalprimaryweapon";  // Mule Kick
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
	// add_to_total = false: restored points aren't new earnings and shouldn't
	// inflate the end-of-game total.
	if( diff > 0 )
		self pb_x_add_to_player_score( diff, false );
	else if( diff < 0 )
		self pb_x_minus_to_player_score( 0 - diff );
}

// give_perk does SetPerk, Juggernog health, the HUD icon and perk_think. Its
// icons for the four newer perks are only precached on maps that have their
// machine, which perks_require_machine (on by default) guarantees.
pb_give_perk( perk )
{
	self pb_x_give_perk( perk, false );
}

pb_max_primaries()
{
	if( self HasPerk( "specialty_additionalprimaryweapon" ) )
		return 3;
	return 2;
}

// Dog (Kino, Der Riese, Shi No Numa remakes) and monkey (Ascension) rounds are
// checked with == on every between_round_over, so a jump past them would end
// them for good. Thief, astronaut, napalm and shrieker checks use >= and sort
// themselves out. `last_unchecked_round` is the last round that won't be checked.
pb_after_round_skip( last_unchecked_round )
{
	if( isDefined( level.next_dog_round ) && level.next_dog_round <= last_unchecked_round )
		level.next_dog_round = last_unchecked_round + randomIntRange( 4, 6 );
	if( isDefined( level.next_monkey_round ) && level.next_monkey_round <= last_unchecked_round )
		level.next_monkey_round = last_unchecked_round + randomIntRange( 4, 6 );
}

// BO1 itself starts later rounds this way (difficulty_init): set the round
// after all players connect and before begin_spawning. round_spawning then
// computes zombie health from round_number. On Moon, No Man's Land copies
// round_number when it starts, so the jump carries through.
pb_set_start_round( target )
{
	waited = 0;
	while( !pb_flag( "all_players_connected" ) )
	{
		wait 0.05;
		waited += 0.05;
		if( waited > 120 )
			return false;
	}
	waittillframeend;
	if( pb_flag( "begin_spawning" ) )
		return false;

	level.first_round = false;
	level.round_number = target;
	// Only set at round rollover by the game, so it has to be set here.
	mult = 8;
	if( isDefined( level.zombie_vars ) && isDefined( level.zombie_vars[ "zombie_move_speed_multiplier" ] ) )
		mult = level.zombie_vars[ "zombie_move_speed_multiplier" ];
	level.zombie_move_speed = ( target - 1 ) * mult;
	if( isDefined( level.zombie_vars ) )
		level.zombie_vars[ "zombie_spawn_delay" ] = pb_spawn_delay_for_round( target );
	pb_after_round_skip( target );
	return true;
}

// --- fallback (round 1 already under way) -----------------------------------

pb_fallback_prepare( target )
{
	// Moon's round 1 is No Man's Land; leaving it restores nml_last_round.
	if( level.pb_mapname == "zombie_moon" && isDefined( level.nml_last_round ) )
	{
		level.nml_last_round = target;
		level.round_number = target;
		return true;
	}
	// BO1's spawner waits while zombie_total <= 0, so this stops round 1.
	level.zombie_total = 0;
	return false;
}

pb_fallback_tick()
{
	level.zombie_total = 0;
}

// No powerup for zombies the round jump kills.
pb_mark_no_reward()
{
	self.no_powerups = true;
}

pb_fallback_done( target )
{
}
