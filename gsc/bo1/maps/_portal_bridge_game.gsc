// =============================================================================
//  Portal Bridge - Call of Duty: Black Ops (BO1) adapter
//
//  Everything that differs between WaW and BO1 zombies lives in this file so
//  the core script compiles unchanged in both games.
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
	if( diff > 0 )
		self pb_x_add_to_player_score( diff );
	else if( diff < 0 )
		self pb_x_minus_to_player_score( 0 - diff );
}

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

// Special rounds are scheduled by round number; push them past the jump.
pb_after_round_skip( round )
{
	if( isDefined( level.next_dog_round ) && level.next_dog_round <= round )
		level.next_dog_round = round + randomIntRange( 4, 7 );
	if( isDefined( level.next_monkey_round ) && level.next_monkey_round <= round )
		level.next_monkey_round = round + randomIntRange( 4, 7 );
	if( isDefined( level.next_thief_round ) && level.next_thief_round <= round )
		level.next_thief_round = round + randomIntRange( 4, 7 );
}
