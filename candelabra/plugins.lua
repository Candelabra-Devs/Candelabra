

--====================================================================--
-- Initialzation                                                      --
--====================================================================--

local CB = candelabra
CB.plugins = {}

local T = CB.gettext

-- central registry of plugin objects
local plugins = {};

--====================================================================--
-- Parser for Plugin Manifest Blocks                                  --
--====================================================================--

local HeaderParser = {};
HeaderParser.__index = file;

function HeaderParser:new (file)
	local this = setmetatable( {}, self );
	this.file = file;
	
    -- initialize the buffer
    this:load();
    this.line_num = 1;
	
	return this;
end

function HeaderParser:load()
	self.index = 1;
	self.content = self.file:Read( 512 );
	return nil ~= self.content;
end

function HeaderParser:readLine()
	local buffer = "";
	
	repeat -- There's no do...while, only repeat...until. Damn Lua.
		local start = self.content:find( "\n", self.index, true );
		if not start then
			buffer = buffer . self.content:sub( self.index );
		else
			buffer = buffer . self.content:sub( self.index, start - 1 );
			self.index = start + 1;
			break;
		end
	until not self:load();
	
	self.line = buffer;
	self.line_num = self.line_num + 1;
	
	return buffer;
end 

function HeaderParser:parse (callback)
	-- skip over the start token
	local match = self.content:match( "%-%-%[=%[Plugin%s\n", self.index );
    if not match then error( T("missing header start token"), 0 ) end
    self.index = self.index + match:length();
    
   	local line = self:readLine();
   	while line do
   		-- check for the header end marker
   		if line:match( "^%s*%]=%]" ) then
   			break;
   		end
   		
   		-- check for leading whitespace, which isn't allowed
   		if line:match( "^%s" ) then
   			error( string.format(
   					T("header line %i: leading whitespace is not allowed"),
   					self.line_num
   				), 0 );
   		end
   		
   		match = line:find( "=", 1, true );
   		if not match then
   			error( T("header line %i: missing ="):format( self.line_num	), 0 );
   		end
   		
   		local key = line:sub( 1, match - 1 ):Trim();
   		local value = line:sub( match + 1 ):Trim();
   		
   		callback( key, value );
   		
   		line = self:readLine();
   	end
end


--====================================================================--
-- Plugin Class                                                       --
--====================================================================--

local meta_normal_keys = {
	name = true,
	author = true,
	version = true,
	description = true,
}

local Plugin = {};
Plugin.__index = Plugin;

--- Parses a plugin's manifest and constucts its Plugin object.
-- @param name the machine name of the plugin
-- @param dir whether the plugin has its own directory
-- @return a Plugin object for the named plugin
local function load_plugin (name, dir)
	local self = setmetatable( {}, Plugin );
	self._name = name;
	self._loaded = false;
	
	-- figure out the path to the plugin's main file
	local path = "/candelabra/plugins/" .. name;
	if dir then
		self._dir = path;
		path = path .. "/init.lua";
	else
		path = path .. ".lua";
	end
	self._file = path;
	
	-- open the file which contains the manifest
	local data = file.Open( file_path, "r", LUA_PATH );
	if not data then
		error( T("unable to open file '%s'"):format( file_path ), 0 );
	end
	
	-- parse the manifest header
	local errors = {};
	local parser = HeaderParser:new( data );
	local ok, message = pcall( parser.parse, parser, function (key, value)
		key = key:lower();
		
		if meta_normal_keys[ key ] then
			local field = "_" .. key;
			if not self[ field ] then
				self[ field ] = value;
			else
				table.insert( errors, string.format(
						T("property '%s' may take at most one value"), key ) );
			end
		elseif "depends" == key then
			if not self._depends then
				self._depends = {};
			end
				
			self._depends[ value ] = true
			
		elseif "x-" == key:sub( 1, 2 ) then
			key = key:sub( 3 );
			
			if not self._ext_meta then
				self._ext_meta = {};
			end
			
			local current = self._ext_meta[ key ]
			if current == nil then
				self._ext_meta[ key ] = value;
			elseif type( current ) == "string" then
				self._ext_meta[ key ] = { current, value };
			else
				table.insert( current, value );
			end
		else
			table.insert( errors, string.format(
					T("unknown property '%s'"), key );
		end
	end );
	
	data:Close();
	
	if not ok then
		table.insert( errors, message );
	end
	
	if #errors > 0 then
		error( table.concat( errors, "\n" ), 0 );
	end
	
	return self;
end

function Plugin:_resolveDependencies()
	local depends = self._depends;
	if not depends then return end
	
	local errors = {};
	for name, value in pairs( depends ) do
		local plugin = plugins[ name ];
		if plugin then
			depends[ name ] = plugin;
		else
			table.insert( errors, string.format(
					T("unresolved dependency '%s'"), name );
		end
	end
	
	if #errors > 0 then
		error( table.concat( errors, "\n" ), 0 );
	end
end


--====================================================================--
-- Find and Load Plugins                                              --
--====================================================================--

do
	local errors = {};

	-- find and load single-file plugins
	local files = file.Find( "candelabra/plugins/*.lua", LUA_PATH );
	for _, file in pairs( files ) do
		local name = file:sub( 1, -4 );
		
		local ok, result = pcall( load_plugin, name, false );
		if ok then
			plugins[ name ] = result;
		else
			errors[ name ] = result;
		end
	end
	
	-- find and load plugins with their own directory
	local _, dirs = file.Find( "candelabra/plugins/*", LUA_PATH );
	for _, name in pairs( dirs ) do
		local ok, result = pcall( load_plugin, name, true );
		if ok then
			plugins[ name ] = result;
		else
			errors[ name ] = result;
		end
	end
	
	-- resolve dependency references
	for name, plugin in pairs( plugins ) do
		local ok, message = pcall( plugin._resolveDependencies, plugin );
		if not ok then
			errors[ name ] = message;
		end
	end
	
	-- print any errors to the server console
	if #errors > 0 then
		for name, message in pairs( errors ) do
			local first = 1;
			while first do
				local match = message:find( "\n", first, true );
				MsgN( string.format(
						T("error in plugin '%s': '%s'"),
						name, message:sub( first, (match or 0) - 1 )
					) );
				
				first = match and match + 1;
			end
		end
	end
end