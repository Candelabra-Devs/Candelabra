--====================================================================--
-- Initialzation                                                      --
--====================================================================--

candelabra = {}

function candelabra.gettext( string )
	return string
end

--====================================================================--
-- Load the Gamemode                                                  --
--====================================================================--

-- Include client files
AddCSLuaFile( "cl_init.lua" );
AddCSLuaFile( "shared.lua"  );

-- Server Init.
include( "shared.lua"  );
include( "plugins.lua" );