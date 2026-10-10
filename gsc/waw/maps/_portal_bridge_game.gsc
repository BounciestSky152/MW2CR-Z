// =============================================================================
//  Portal Bridge - Call of Duty: World at War adapter
//
//  Everything that differs between WaW and BO1 zombies lives in this file so
//  the core script compiles unchanged in both games.
// =============================================================================

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
		self maps\_zombiemode_score::add_to_player_score( diff );
	else if( diff < 0 )
		self maps\_zombiemode_score::minus_to_player_score( 0 - diff );
}

// Mirrors what vending_trigger_think does after the bottle animation.
pb_give_perk( perk )
{
	self SetPerk( perk );

	if( perk == "specialty_armorvest" )
	{
		health = 160;
		if( isDefined( level.zombie_vars[ "zombie_perk_juggernaut_health" ] ) )
			health = level.zombie_vars[ "zombie_perk_juggernaut_health" ];
		self.maxhealth = health;
		self.health = health;
	}

	self maps\_zombiemode_perks::perk_hud_create( perk );
	self thread maps\_zombiemode_perks::perk_think( perk );
}

pb_max_primaries()
{
	return 2;
}

// Special rounds are scheduled by round number; push them past the jump.
pb_after_round_skip( round )
{
	if( isDefined( level.next_dog_round ) && level.next_dog_round <= round )
		level.next_dog_round = round + randomIntRange( 4, 7 );
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
