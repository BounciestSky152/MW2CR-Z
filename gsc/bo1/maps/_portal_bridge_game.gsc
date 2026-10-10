// =============================================================================
//  Portal Bridge - Call of Duty: Black Ops (BO1) adapter
//
//  Everything that differs between WaW and BO1 zombies lives in this file so
//  the core script compiles unchanged in both games.
// =============================================================================

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
		self maps\_zombiemode_score::add_to_player_score( diff );
	else if( diff < 0 )
		self maps\_zombiemode_score::minus_to_player_score( 0 - diff );
}

pb_give_perk( perk )
{
	self maps\_zombiemode_perks::give_perk( perk, false );
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

pb_engine_changelevel( mapname )
{
	changelevel( mapname, false );
}

// Needs developer_script 1 and logfile 1/2 so it reaches the console log the
// bridge tails (the bridge's default launch arguments set both).
pb_emit( line )
{
	println( line );
}
