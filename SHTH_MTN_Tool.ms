/*
	Shadow the Hedgehog .MTN tool

	-Huge Thanks to TGE for function(s) from other scripts
	
	------------------------------------------------------------------------------------------
	
		.MTN/SHTHanim
		0x0		U8Int  0x4
		0x1		U8Int  Endianness 0 for little endian, 1 for big endian
		0x2		U16Int 0x0
		0x4		U32Int 0x0
		0x8		U32Int Filesize
		0xC		U8Int  0xFF
		0xD		U8Int  0x07
		0xE		U16Int 0x0
		0xF		U16Int Unknown Short1
		0x12	U16Int Unknown Short2
		0x14	char[0x20] modelname
		0x34	header_end, structs start

		while(!end_of_file)
		{
			// Struct header
			0x0		U32Int Structlength
			0x4		U16Int Amount of keyframes
			0x6		U8Int  Padding flag; 0 or 2
			0x7		U8Int  1 unless last strip of file. Last of file is 0
			0x8		struct_header_end, keyframes start
			
			for (i = 1; i < Amount of keyframes; i++)
			{
				0x0		U16Int  Keyframe Time
				0x2		U16Int? Keyframe data1
				0x4		U16Int? Keyframe data2
				0x6		keyframe_end, next keyframe starts
			}
			
			if(StructLength % 4 > 0)
			(
				padding of StructLength % 4 (generally two 0x0 bytes)
			)
		}
	
	
*/
ClearListener()
FileIn @"include\MaxScriptExtensions\FileStreamReader.ms"
FileIn @"include\MaxScriptExtensions\FileUtils.ms"

rollout bonImport ".STHANIM Importer"
(
--------------------
-- User Interface --
--------------------
group "About"
(
	label lab1 "Shadow TH .STHANIM Importer"
	Label lab2 "By Shadowth117"
)
group "Settings"
(
	/*
	checkBox hApply "Apply to hierarchy" checked:true align:#center
	checkBox autoSizeCheckBox "Rescale" checked:false align:#center
	spinner autoSizeSpinner "Scale by:" align:#center type:#float range:[0,10000,100] enabled:false
	checkBox YZCheckBox "Y-Z Axis Flip" checked:false align:#center	
*/
)	
group "Import"
(
	button importButton "Import...(Broken)"
	checkBox oldImp "OldMethod" checked:true align:#center
)
group "Export"
(
	button exportButton "Export..."
	checkBox bigEnd "Big Endian" checked:true align:#center
	edittext anmName "EntityID, 20 characters max" fieldWidth:90 labelOnTop:true align:#center
)

--Relative Position Getter
fn relativePosition obj keyTime =
(
	tfm = (at time keyTime obj.transform)
	if obj.Parent != undefined then
	(
		--tfm *= (inverse (relativePosition obj.Parent keyTime)) 
		tfm *= (inverse (at time keyTime obj.Parent.transform)) 
	)
	
	tfm
)

--For converting F32s to F16s
struct floatCompressor
(
	--Implementing algorithm by Jeroen van der Zijp in "Fast Half Float Conversions" half float conversion algorithm
	shANM,
	basetable,
	shifttable,
	bigEndian,
	
	on create do
	(
		basetable = #() --initialize these as arrays
		shifttable = #()
		for i = 1 to 256 do
		(
			f = i-127
			if f < -24 then
			(-- Very small numbers map to zero
				basetable[bit.or i 0x000] = 0x0000
				basetable[bit.or i 0x100] = 0x8000
				shifttable[bit.or i 0x000] = 24
				shifttable[bit.or i 0x100] = 24
			)
			else if f < -14 then
			( -- Small numbers map to denorms
				basetable[bit.or i 0x000] = (bit.shift 0x0400 -(-f-14)) --In maxscript, bitshifting right requires a negative number. Likewise, shifting left requires positive
				basetable[bit.or i 0x100] = bit.or (bit.shift 0x0400 -(-f-14)) 0x8000
				shifttable[bit.or i 0x000] = -f-1
				shifttable[bit.or i 0x100] = -f-1
			)
			else if f <= 15 then
			(-- Normal numbers just lose precision
				basetable[bit.or i 0x000] = (bit.shift (f+15) 10)
				basetable[bit.or i 0x100] = bit.or (bit.shift (f+15) 10) 0x8000
				shifttable[bit.or i 0x000] = 13
				shifttable[bit.or i 0x100] = 13
			)
			else if f < 128 then
			( -- Large numbers map to Infinity
				basetable[bit.or i 0x000] = 0x7C00
				basetable[bit.or i 0x100] = 0xFC00
				shifttable[bit.or i 0x000] = 24
				shifttable[bit.or i 0x100] = 24
			)
			else
			( -- Infinity and NaN's stay Infinity and NaN's
				basetable[bit.or i 0x000] = 0x7C00
				basetable[bit.or i 0x100] = 0xFC00
				shifttable[bit.or i 0x000] = 13
				shifttable[bit.or i 0x100] = 13
			)
		)
	),
	
	public fn GetFileStream =
	(
		shANM
	),
	
	public fn SetFile aFilePath aIsBigEndian = 
	(
		bigEndian = aIsBigEndian
		shANM = FOpen aFilePath "wb"
	),
	
	public fn Close =
	(
		FFlush shANM
		FClose shANM
		shANM = undefined
	),
	
	fn FloatCompare float1 float2 eps =
	(
		test = false
		if float1 == float2 then
		( 
			test = true
		) 
		else if (abs(abs(float1) - abs(float2)) < eps) then
		(
			test = true
		) 
		
		test
	),
	
	fn WriteU16 U32 =
	(	
		U16 = U32
		if bigEndian == true then
		(
			U16 = bit.intashex U16
			while U16.count < 4 do
			(
				U16 = "0" + U16
			)
			U16 = (substring U16 (U16.count - 3) U16.count)
			U16 = bit.hexasint U16
			U16 = Bit.SwapBytes U16 1 2
		)
		WriteShort shANM U16
	),
	
	fn WriteU32 U32 =
	(
		U32W = U32
		if bigEndian == true then
		(
			U32W = (Bit.SwapBytes (Bit.SwapBytes (U32W) 1 4) 2 3)
		)
		WriteLong shANM U32W
		
	),
	
	fn WriteF16 f32float =
	(
		if (FloatCompare f32float 0 0.00001) == true then
		(
			WriteShort shANM 0
		) else 
		(
			f32 = bit.floatAsInt f32float
			f16 = basetable[bit.and (bit.shift f32 -23) 0x1ff]+(bit.shift (bit.and f32 0x007fffff) -(shifttable[bit.and (bit.shift f32 -23) 0x1ff]))

			if bigEndian == true then
			(
				f16 = Bit.SwapBytes f16 1 2
				WriteShort shANM f16
			) else
			(
				WriteShort shANM f16
			)
		)
	),
	
	fn WriteF32 F32 =
	(
		F32W = Bit.FloatAsInt F32
		if bigEndian == true then
		(
			F32W = (Bit.SwapBytes (Bit.SwapBytes (F32W) 1 4) 2 3)
		)
		WriteLong shANM F32W
		
	),
	
	fn WriteKeySet o ctrl xyz firstNode =
	(
		--Write struct
		addEnd = false
		sortKeys ctrl
		keyCount = ctrl.keys.count
		--Figure out structLength in advance
		if (keyCount > 1) then
		(
			if (ctrl.keys[keyCount].time) != animationrange.end then --Anims should have an end keyframe. May cause weirdness otherwise
			(
				addEnd = true
			)
			structLength = (keyCount * 6 + 0x8)
		) else if firstNode == false then
		(
			addEnd = true
			structLength = (0x14)
		) else
		(
			structLength = (0x10)
		)
		--StructHeader
		WriteU32 structLength
		WriteU16 keyCount
		padding = (mod (structLength - 0x8) 0x6)
		WriteByte shANM padding
		WriteByte shANM 0x1
		--Write keys
		if (keyCount > 0) then
		(
			for itemKey in ctrl.keys do 
			(
				WriteU16 (itemKey.Time + 0xC000) --Time is keyframe time + 0xC000
				if itemKey.outTangentType == #custom then
				(
					interp = itemKey.outTangent
				) else
				(
					interp = 0
				)
				WriteF16 interp
				case xyz of
				(
					"": WriteF16 (itemKey.value * (pi/180));
					".px": WriteF16 (relativePosition o itemKey.Time).translationpart.x
					".py": WriteF16 (relativePosition o itemKey.Time).translationpart.y
					".pz": WriteF16 (relativePosition o itemKey.Time).translationpart.z
					".x": WriteF16 itemKey.value.x;
					".y": WriteF16 itemKey.value.y;
					".z": WriteF16 itemKey.value.z;
				)
			)
		) else
		(
			WriteU16 0xC000
			WriteU16 0
			case xyz of
			(
				"": WriteF16 (ctrl.value * (pi/180));
				".px": WriteF16 (relativePosition o 0).translationpart.x
				".py": WriteF16 (relativePosition o 0).translationpart.y
				".pz": WriteF16 (relativePosition o 0).translationpart.z
				".x": WriteF16 ctrl.value.x;
				".y": WriteF16 ctrl.value.y;
				".z": WriteF16 ctrl.value.z;
			)
		)
		if addEnd == true then
		(
			if keyCount > 0 then
			(
				WriteU16 (animationrange.end + 0xC000) --Time is keyframe time + 0xC000
				WriteU16 0
				case xyz of
				(
					"": WriteF16 (ctrl.keys[keyCount].value * (pi/180));
					".px": WriteF16 (relativePosition o ctrl.keys[keyCount].time).translationpart.x
					".py": WriteF16 (relativePosition o ctrl.keys[keyCount].time).translationpart.y
					".pz": WriteF16 (relativePosition o ctrl.keys[keyCount].time).translationpart.z
					".x": WriteF16 ctrl.keys[keyCount].value.x;
					".y": WriteF16 ctrl.keys[keyCount].value.y;
					".z": WriteF16 ctrl.keys[keyCount].value.z;
				)
			)
		)
		--padding
		if (padding > 0) then
		(
			for i = 1 to padding do
			(
				WriteByte shANM 0
			)
		)
	),
	
	fn MTNWrite = 
	(
		--Write anim
		WriteByte shANM 0x4			--0x4 - Filetyping
		if bigEndian == true then   --Endianness, 0 for little, 1 for big
		(
			WriteByte shANM 0x1
		) else
		(
			WriteByte shANM 0x0
		)
		WriteU16 0x0
		WriteU32 0x0
		fileSizeOff = (ftell shANM) 
		WriteU32 0x0			--File size. Offset stored to fill in later
		WriteByte shANM 0xFF		--Version?
		WriteByte shANM 0x07		--Version?
		WriteU16 0x0
		WriteU16 0x0		--Unk u16
		WriteU16 0x0		--Unk u16
		charName = (substring anmName.text 1 0x20)
		extraSpace = 0x20 - (charName.count) --calculate space left to 20 (if any)
		WriteString shANM charName --0x20 string for animation id (ex. sh for shadow)
		fseek shANM (-1) #seek_cur
		for e = 1 to extraSpace do -- add padding to reach 0x20 if needed
		(
			writeByte shANM 0x0
		)
		
		--Write data for each valid node
		--Data past first node MUST have start and end keyframes!
		firstNode = true
		lastStrAdd = undefined
		for o in objects do
		(
			local indexProp = GetUserProp o "tag"
			if ( indexProp != undefined ) then
			(
				if firstNode == false then
				(
					--Write x scale
					WriteKeySet o o.scale.controller ".x" firstNode
					WriteKeySet o o.scale.controller ".y" firstNode
					WriteKeySet o o.scale.controller ".z" firstNode
				)
				
				WriteKeySet o o.pos.x_position.controller ".px" firstNode
				WriteKeySet o o.pos.y_position.controller ".py" firstNode
				WriteKeySet o o.pos.z_position.controller ".pz" firstNode
				WriteKeySet o o.rotation.x_rotation.controller "" firstNode
				WriteKeySet o o.rotation.y_rotation.controller "" firstNode
				WriteKeySet o o.rotation.z_rotation.controller "" firstNode
				for i = 1 to 3 do
				(
					if firstNode == false then
					(
						WriteU32 0x14
						WriteU16 0x2
						WriteByte shANM 0x0
						lastStrAdd = ftell shANM 
						WriteByte shANM 0x1
						WriteU16 0xC000
						WriteU16 0
						WriteU16 0x3C00 --1.0 as f16
						
						WriteU16 (animationrange.end + 0xC000)
						WriteU16 0
						WriteU16 0x3C00 --1.0 as f16
					) else
					(
						WriteU32 0x10
						WriteU16 0x1
						WriteByte shANM 0x2
						lastStrAdd = ftell shANM 
						WriteByte shANM 0x1
						WriteU16 0xC000
						WriteU16 0
						WriteU16 0x3C00 --1.0 as f16
						WriteU16 0      --padding
					)
				)
				firstNode = false
			)
		)
		
		fileSize = ftell shANM
		fseek shANM lastStrAdd #seek_set
		WriteByte shANM 0
		fseek shANM fileSizeOff #seek_set
		WriteU32 fileSize
		FFlush shANM
		FClose shANM
	)
)

struct KeyFrame
(
	Data1,
	Data2,
	Timing
)

struct FullKey
(
	Timing,
	XScale,
	YScale,
	ZScale,
	XPos,
	YPos,
	ZPos,
	XRot,
	YRot,
	ZRot,
	XScaleW,
	YScaleW,
	ZScaleW,
	XScale2,
	YScale2,
	ZScale2,
	XPos2,
	YPos2,
	ZPos2,
	XRot2,
	YRot2,
	ZRot2,
	XScaleW2,
	YScaleW2,
	ZScaleW2
)

struct BoneStruct 
(
	BoneOrder,
	BoneTag,
	BoneUnkInt,
	BoneShort,
	BoneSplitID,
	BoneParamID,
	BoneParent,
	ParInt,
	SibInt,
	BoneName,
	BoneTFM,
	MaxBone,
	BonePRSPosition,
	BonePRSRotation,
	BonePRSScale
)

fn getKeyAtTime ctrl timing =
(
	keyTime = getKeyIndex ctrl timing
	if keyTime != undefined and keyTime != 0 then
	(
		key = getKey ctrl (keyTime)
	) else
	(
		key = undefined
	) 
	
	key
)	

fn SkelImport0 aqnFile =
(
	keyFrames = #()
	keySet = #()
	animLength = 1
	
	-- Read file
	local reader = FileStreamReader()
	reader.SetFile aqnFile false
	reader.SetBigEndian true
	
	fileType = reader.ReadU8()                  --Should be 4 or it's not an MTN
	endian = reader.ReadU8()
	if endian == 0 then
	(
		reader.SetBigEndian false
	)
	reader.SeekCur( 0x6)						--Always 0
	fileSize = reader.ReadU32()
	setInt = reader.ReadU32()
	shortInt1 = reader.ReadU16()
	shortInt2 = reader.ReadU16()
	charID = reader.ReadFixedLengthString 0x20
	
	--Read Keys
	structCount = -1
	keyType = 3
	currentNode = 1
	keySet[currentNode] =  FullKey()
	--print (reader.GetFileStreamLength() as string)
	--print ("--------------- Node 1")
	while reader.GetPosition() < reader.GetFileStreamLength() do
	(
		structData = #()
		structUnk = #()
		structTiming = #()
		structStart = reader.GetPosition()
		if keyType >= 12 then
		(
			currentNode += 1
			--print ("--------------- Node " + currentNode as string)
			keyType = 1
			append keyFrames (deepcopy keySet)
			free keySet
			keySet = #()
			
		) else
		(
			keyType += 1
		)
		--print ("Address: " + structStart as string)
		
		structCount += 1
		structLength = reader.ReadU32()
		--reader.SeekCur( structLength - 0x4 )
		paramShort = reader.ReadU16()	--Amount of data values 
		paramByte1 = reader.ReadU8()	--Padding at end. 0 or 2. Structs MUST be multiples of 4 so this is needed
		paramByte2 = reader.ReadU8()	--Value is 1 until the last strip

		--padding = paramByte1
		padding = mod (structLength - 0x8)  0x6

		keysLength = ((structLength - 0x8) / 0x6)
		for i = 1 to keysLength do
		(
			--Record Keyframe "header"
			timing = abs(reader.ReadU16() - 0xC000) + 1	--Timing
			if timing > animLength then
			(
				animLength = timing
			)
			data1 = (( (reader.ReadF16())) )	--FrameData
			data2 = (( (reader.ReadF16())) )  --FrameData
			

			frameUnk = data1
			frame = data2
			
			append structUnk frameUnk
			append structTiming timing
			append structData frame
		)
		reader.SeekCur( padding )
		
		--print ( "Address: " + (bit.intashex structStart) + " " + "Strip " + (structCount as string) + " " + "StructLength: " + (structLength as string) + " " + "Value Count: " + (paramShort as string) + " " + "Padding: "+ (paramByte1 as string) + " " + "Last if 0: " + (paramByte2 as string) )
		
		/*
		case keyType of
		(
			1:  print "X Scale"
			2:  print "Y Scale"
			3:  print "Z Scale"
			4:  print "X Position"
			5:  print "Y Position"
			6:  print "Z Position"
			7:  print "X Rotation"
			8:  print "Y Rotation"
			9:  print "Z Rotation"
			10: print "X Scale (Weird)"
			11: print "Y Scale (Weird)"
			12: print "Z Scale (Weird)"
		)*/
		
		for i = 1 to structTiming.count do
		(
			/*
			print ("key " + (i as string))
			print structTiming[i]
			print structUnk[i]
			print structData[i]
			*/
			
			if structTiming[i] > keySet.count then
			(
				keySet[structTiming[i]] = FullKey()
			)
			if keySet[structTiming[i]] == undefined then
			(
				keySet[structTiming[i]] = FullKey()
			)
			
			case keyType of
			(
				1: 
				(
					keySet[structTiming[i]].XScale = structData[i]
					keySet[structTiming[i]].XScale2 = structUnk[i]
				)
				2: 			
				(
					keySet[structTiming[i]].YScale = structData[i]
					keySet[structTiming[i]].YScale2 = structUnk[i]
				)				
				3:
				(
					keySet[structTiming[i]].ZScale = structData[i]
					keySet[structTiming[i]].ZScale2 = structUnk[i]
				)
				4:
				(
					keySet[structTiming[i]].XPos = structData[i]
					keySet[structTiming[i]].XPos2 = structUnk[i]
				)
				5:
				(
					keySet[structTiming[i]].YPos = structData[i]
					keySet[structTiming[i]].YPos2 = structUnk[i]
				)
				6:
				(
					keySet[structTiming[i]].ZPos = structData[i]
					keySet[structTiming[i]].ZPos2 = structUnk[i]
				)
				7:
				(
					keySet[structTiming[i]].XRot = structData[i]
					keySet[structTiming[i]].XRot2 = structUnk[i]
				)
				8:
				(
					keySet[structTiming[i]].YRot = structData[i]
					keySet[structTiming[i]].YRot2 = structUnk[i]
				)
				9:  
				(
					keySet[structTiming[i]].ZRot = structData[i]
					keySet[structTiming[i]].ZRot2 = structUnk[i]
				)
				10: 
				(
					keySet[structTiming[i]].XScaleW = structData[i]
					keySet[structTiming[i]].XScaleW2 = structUnk[i]
				)
				11:
				(
					keySet[structTiming[i]].YScaleW = structData[i]
					keySet[structTiming[i]].YScaleW2 = structUnk[i]
				)
				12:
				(
					keySet[structTiming[i]].ZScaleW = structData[i]
					keySet[structTiming[i]].ZScaleW2 = structUnk[i]
				)
			)
			
		)
		
		
		
		/*
		kf = Keyframe()
		kf.Data1 = structUnk
		kf.Data2 = structData
		kf.Timing = structTiming
		
		append keyFrames kf
		*/
		
	)
	append keyFrames keySet
	free keySet
	reader.Close()
	print "File read"
	
	--Apply Animation Data
	framerate = 60
	animationRange = interval 0 (animLength-1)
	
	--Gather nodes
	local nodes = #()
	local nodecount = 0;
	for o in objects do
	(
		local indexProp = GetUserProp o "tag"
		if ( indexProp != undefined ) then
		(
			nodecount += 1;
			nodes[ nodecount ] = o
		)
	)
	
	--Apply to nodes
	with animate on
	(
		maxops.setDefaultTangentType #smooth #smooth
		for i = 1 to currentNode while i <= nodecount do 
		(
			for j = 1 to keyframes[i].count do
			(
				if keyFrames[i][j] != undefined then
				(
					at time (j - 1)
					(
						
						--Assign rotation keys
						if(keyFrames[i][j].XRot != undefined and keyFrames[i][j].YRot != undefined and keyFrames[i][j].ZRot != undefined) then
						(
							nodes[i].Controller.Rotation = eulertoquat (eulerangles (keyFrames[i][j].XRot * (180/pi)) (keyFrames[i][j].YRot * (180/pi)) (keyFrames[i][j].ZRot * (180/pi)))
						) else
						(
							
							rot = (quattoeuler2 nodes[i].Controller.Rotation)
							if (keyFrames[i][j].XRot != undefined) then
							(
								rot.x = keyFrames[i][j].XRot * (180/pi)
							)
							if (keyFrames[i][j].YRot != undefined) then
							(
								rot.y = keyFrames[i][j].YRot * (180/pi)
							)
							if (keyFrames[i][j].ZRot != undefined) then
							(
								rot.z = keyFrames[i][j].ZRot * (180/pi)
							)
							nodes[i].Controller.Rotation = (eulertoquat rot)
							
							--No matter the method, max makes keyframes for the other angles. Delete what we're not applying
							if (keyFrames[i][j].XRot == undefined) then
							(
								selectKeys nodes[i].rotation.x_rotation.controller (j - 1)
								deleteKeys nodes[i].rotation.x_rotation.controller.keys #selection
							)
							if (keyFrames[i][j].YRot == undefined) then
							(
								selectKeys nodes[i].rotation.y_rotation.controller (j - 1)
								deleteKeys nodes[i].rotation.y_rotation.controller.keys #selection
							)
							if (keyFrames[i][j].ZRot == undefined) then
							(
								selectKeys nodes[i].rotation.z_rotation.controller (j - 1)
								deleteKeys nodes[i].rotation.z_rotation.controller.keys #selection
							)
						)
						
						--Assign translation keys
						if (keyFrames[i][j].XPos != undefined) then
						(
							nodes[i].Controller.Position.x = keyFrames[i][j].XPos
						)
						if (keyFrames[i][j].YPos != undefined) then
						(
							nodes[i].Controller.Position.y = keyFrames[i][j].YPos
						)
						if (keyFrames[i][j].ZPos != undefined) then
						(
							nodes[i].Controller.Position.z = keyFrames[i][j].ZPos
						)
						
						--Delete unapplied keys
						if (keyFrames[i][j].XPos == undefined) then
						(
							selectKeys nodes[i].pos.x_position.controller (j - 1)
							deleteKeys nodes[i].pos.x_position.controller.keys #selection
						)
						if (keyFrames[i][j].YPos == undefined) then
						(
							selectKeys nodes[i].pos.y_position.controller (j - 1)
							deleteKeys nodes[i].pos.y_position.controller.keys #selection
						)
						if (keyFrames[i][j].ZPos == undefined) then
						(
							selectKeys nodes[i].pos.z_position.controller (j - 1)
							deleteKeys nodes[i].pos.z_position.controller.keys #selection
						)
						
						--Assign scale keys.... unfortunately cannot delete unused scaling keys
						if (keyFrames[i][j].XScale != undefined) then
						(
							nodes[i].Controller.Scale.x = keyFrames[i][j].XScale
						)
						if (keyFrames[i][j].YScale != undefined) then
						(
							nodes[i].Controller.Scale.y = keyFrames[i][j].YScale
						)
						if (keyFrames[i][j].ZScale != undefined) then
						(
							nodes[i].Controller.Scale.z = keyFrames[i][j].ZScale
						)
						
					)
				)
			)
		)
	)
	
	
	/*
	--Apply to nodes (The root node only has 9 keyframes. Since structCount is 0 based, we subtract 8, divide by 12 (num of key structs per node), add 1 for the root, and apply)
	--Nodecount is calculated at all in order to attempt to apply in the case of extra nodes
	
	with animate on
	(
		maxops.setDefaultTangentType #smooth #smooth
		for i = 1 to (((structCount - 8) / 12) + 1) while i <= nodecount do 
		(
			print " "
			print ("Node: " + (i) as string)
			
			--Set keyID based on progress 
			if (i > 1) then
			(
				keyID = (i - 1) * 12 - 3
			) else
			(
				keyID = 0
			)
			
			if i > 1 then
			(
				keyID += 1
				--X true scale keyframes
				for j = 1 to keyframes[keyID].Timing.count do
				(
					if (keyframes[keyID].Timing[j] < 0xC000 and keyframes[keyID].Timing[j] > -1) then
					(
						at time (keyframes[keyID].Timing[j])
						(
							nodes[i].Controller.Scale.x = keyframes[keyID].Data2[j]
						)
					)
				)
				keyID += 1
				--Y true scale keyframes
				for j = 1 to keyframes[keyID].Timing.count do
				(
					if (keyframes[keyID].Timing[j] < 0xC000 and keyframes[keyID].Timing[j] > -1) then
					(
						at time (keyframes[keyID].Timing[j])
						(
							nodes[i].Controller.Scale.y = keyframes[keyID].Data2[j]
						)
					)
				)
				keyID += 1
				--Z true scale keyframes
				for j = 1 to keyframes[keyID].Timing.count do
				(	
					if (keyframes[keyID].Timing[j] < 0xC000 and keyframes[keyID].Timing[j] > -1) then
					(
						at time (keyframes[keyID].Timing[j])
						(
							nodes[i].Controller.Scale.z = keyframes[keyID].Data2[j]
						)
					)
				)
			)
			
			keyID += 1
			--X Translation keyframes
			print "x pos"
			for j = 1 to keyframes[keyID].Timing.count do
			(
				if (keyframes[keyID].Timing[j] < 0xC000 and keyframes[keyID].Timing[j] > -1) then
				(	
					at time (keyframes[keyID].Timing[j])
					(
						nodes[i].Controller.Position.x = keyframes[keyID].Data2[j]
						print ((time as string) + " " + (keyframes[keyID].Timing[j] as string) + ": " + (keyframes[keyID].Data2[j] as string)) 
					)
				)
			)
			keyID += 1
			--Y Translation keyframes
			print "y pos"
			for j = 1 to keyframes[keyID].Timing.count do
			(
				if (keyframes[keyID].Timing[j] < 0xC000 and keyframes[keyID].Timing[j] > -1) then
				(	
					at time (keyframes[keyID].Timing[j])
					(
						nodes[i].Controller.Position.y = keyframes[keyID].Data2[j]
						print ((time as string) + " " + (keyframes[keyID].Timing[j] as string) + ": " + (keyframes[keyID].Data2[j] as string)) 
					)
				)
			)
			keyID += 1
			--Z Translation keyframes
			print "z pos"
			for j = 1 to keyframes[keyID].Timing.count do
			(
				if (keyframes[keyID].Timing[j] < 0xC000 and keyframes[keyID].Timing[j] > -1) then
				(	
					at time (keyframes[keyID].Timing[j])
					(
						nodes[i].Controller.Position.z = keyframes[keyID].Data2[j]
						print ((time as string) + " " + (keyframes[keyID].Timing[j] as string) + ": " + (keyframes[keyID].Data2[j] as string)) 
					)
				)
			)
			
			keyID += 1
			--X rotation keyframes
			print "x rot"
			for j = 1 to keyframes[keyID].Timing.count do
			(
				if (keyframes[keyID].Timing[j] < 0xC000 and keyframes[keyID].Timing[j] > -1) then
				(	
					at time (keyframes[keyID].Timing[j])
					(
						rot = (quattoeuler2 nodes[i].Controller.Rotation)
						rot.x = keyframes[keyID].Data2[j] * (180/pi)
						nodes[i].Controller.Rotation = (eulertoquat rot)
						print ((time as string) + " " + (keyframes[keyID].Timing[j] as string) + ": " + ((keyframes[keyID].Data2[j] * (180/pi)) as string)) 
					)
				)
			)
			keyID += 1
			--Y rotation keyframes
			print "y rot"
			for j = 1 to keyframes[keyID].Timing.count do
			(
				if (keyframes[keyID].Timing[j] < 0xC000 and keyframes[keyID].Timing[j] > -1) then
				(	
					at time (keyframes[keyID].Timing[j])
					(
						rot = (quattoeuler2 nodes[i].Controller.Rotation)
						rot.y = keyframes[keyID].Data2[j] * (180/pi)
						nodes[i].Controller.Rotation = (eulertoquat rot)
						print ((time as string) + " " + (keyframes[keyID].Timing[j] as string) + ": " + ((keyframes[keyID].Data2[j] * (180/pi)) as string)) 
					)
				)
			)
			keyID += 1
			--Z rotation keyframes
			print "z rot"
			for j = 1 to keyframes[keyID].Timing.count do
			(
				if (keyframes[keyID].Timing[j] < 0xC000 and keyframes[keyID].Timing[j] > -1) then
				(	
					at time (keyframes[keyID].Timing[j])
					(
						rot = (quattoeuler2 nodes[i].Controller.Rotation)
						rot.z = keyframes[keyID].Data2[j] * (180/pi)
						nodes[i].Controller.Rotation = (eulertoquat rot)
						print ((time as string) + " " + (keyframes[keyID].Timing[j] as string) + ": " + ((keyframes[keyID].Data2[j] * (180/pi)) as string)) 
					)
				)
			)
			
			
			print "weird xscale keys"
			keyID += 1
			--X scale keyframes
			for j = 1 to keyframes[keyID].Timing.count do
			(
				at time (keyframes[keyID].Timing[j])
				(
					print keyframes[keyID].Data2[j]
				)
			)
			print "weird yscale keys"
			keyID += 1
			--Y scale keyframes
			for j = 1 to keyframes[keyID].Timing.count do
			(
				at time (keyframes[keyID].Timing[j])
				(
					print keyframes[keyID].Data2[j]
				)
			)
			print "weird zscale keys"
			keyID += 1
			--Z scale keyframes
			for j = 1 to keyframes[keyID].Timing.count do
			(
				at time (keyframes[keyID].Timing[j])
				(
					print keyframes[keyID].Data2[j]
				)
			)
			
		)
	)*/
	
)

fn SkelImport aqnFile =
(
	keyFrames = #()
	keySet = #()
	animLength = 1
	
	-- Read file
	local reader = FileStreamReader()
	reader.SetFile aqnFile false
	reader.SetBigEndian true
	
	fileType = reader.ReadU8()                  --Should be 4 or it's not an MTN
	endian = reader.ReadU8()
	if endian == 0 then
	(
		reader.SetBigEndian false
	)
	reader.SeekCur( 0x6)						--Always 0
	fileSize = reader.ReadU32()
	setInt = reader.ReadU32()
	shortInt1 = reader.ReadU16()
	shortInt2 = reader.ReadU16()
	charID = reader.ReadFixedLengthString 0x20
	
	--Read Keys
	structCount = -1
	keyType = 3
	currentNode = 1
	keySet[currentNode] =  FullKey()
	--print (reader.GetFileStreamLength() as string)
	--print ("--------------- Node 1")
	while reader.GetPosition() < reader.GetFileStreamLength() do
	(
		structData = #()
		structUnk = #()
		structTiming = #()
		structStart = reader.GetPosition()
		if keyType >= 12 then
		(
			currentNode += 1
			--print ("--------------- Node " + currentNode as string)
			keyType = 1
			append keyFrames (deepcopy keySet)
			free keySet
			keySet = #()
			
		) else
		(
			keyType += 1
		)
		--print ("Address: " + structStart as string)
		
		structCount += 1
		structLength = reader.ReadU32()
		paramShort = reader.ReadU16()	--Amount of data values 
		paramByte1 = reader.ReadU8()	--Padding at end. 0 or 2. Structs MUST be multiples of 4 so this is needed
		paramByte2 = reader.ReadU8()	--Value is 1 until the last strip

		padding = mod (structLength - 0x8)  0x6

		keysLength = ((structLength - 0x8) / 0x6)
		for i = 1 to keysLength do
		(
			--Record Keyframe "header"
			timing = abs(reader.ReadU16() - 0xC000) + 1	--Timing
			if timing > animLength then
			(
				animLength = timing
			)
			data1 = (( (reader.ReadF16())) )	--FrameData
			data2 = (( (reader.ReadF16())) )  --FrameData
			

			frameUnk = data1
			frame = data2
			
			append structUnk frameUnk
			append structTiming timing
			append structData frame
		)
		reader.SeekCur( padding )
		
		--print ( "Address: " + (bit.intashex structStart) + " " + "Strip " + (structCount as string) + " " + "StructLength: " + (structLength as string) + " " + "Value Count: " + (paramShort as string) + " " + "Padding: "+ (paramByte1 as string) + " " + "Last if 0: " + (paramByte2 as string) )
		
		/*
		case keyType of
		(
			1:  print "X Scale"
			2:  print "Y Scale"
			3:  print "Z Scale"
			4:  print "X Position"
			5:  print "Y Position"
			6:  print "Z Position"
			7:  print "X Rotation"
			8:  print "Y Rotation"
			9:  print "Z Rotation"
			10: print "X Scale (Weird)"
			11: print "Y Scale (Weird)"
			12: print "Z Scale (Weird)"
		)*/
		
		
		for i = 1 to structTiming.count do
		(
			/*
			print ("key " + (i as string))
			print structTiming[i]
			print structUnk[i]
			print structData[i]
			*/
			
			if structTiming[i] > keySet.count then
			(
				keySet[structTiming[i]] = FullKey()
			)
			if keySet[structTiming[i]] == undefined then
			(
				keySet[structTiming[i]] = FullKey()
			)
			
			case keyType of
			(
				1: 
				(
					keySet[structTiming[i]].XScale = structData[i]
					keySet[structTiming[i]].XScale2 = structUnk[i]
				)
				2: 			
				(
					keySet[structTiming[i]].YScale = structData[i]
					keySet[structTiming[i]].YScale2 = structUnk[i]
				)				
				3:
				(
					keySet[structTiming[i]].ZScale = structData[i]
					keySet[structTiming[i]].ZScale2 = structUnk[i]
				)
				4:
				(
					keySet[structTiming[i]].XPos = structData[i]
					keySet[structTiming[i]].XPos2 = structUnk[i]
				)
				5:
				(
					keySet[structTiming[i]].YPos = structData[i]
					keySet[structTiming[i]].YPos2 = structUnk[i]
				)
				6:
				(
					keySet[structTiming[i]].ZPos = structData[i]
					keySet[structTiming[i]].ZPos2 = structUnk[i]
				)
				7:
				(
					keySet[structTiming[i]].XRot = structData[i]
					keySet[structTiming[i]].XRot2 = structUnk[i]
				)
				8:
				(
					keySet[structTiming[i]].YRot = structData[i]
					keySet[structTiming[i]].YRot2 = structUnk[i]
				)
				9:  
				(
					keySet[structTiming[i]].ZRot = structData[i]
					keySet[structTiming[i]].ZRot2 = structUnk[i]
				)
				10: 
				(
					keySet[structTiming[i]].XScaleW = structData[i]
					keySet[structTiming[i]].XScaleW2 = structUnk[i]
				)
				11:
				(
					keySet[structTiming[i]].YScaleW = structData[i]
					keySet[structTiming[i]].YScaleW2 = structUnk[i]
				)
				12:
				(
					keySet[structTiming[i]].ZScaleW = structData[i]
					keySet[structTiming[i]].ZScaleW2 = structUnk[i]
				)
			)
			
		)
		
	)
	append keyFrames keySet
	free keySet
	reader.Close()
	print "File read"
	
	--Apply Animation Data
	framerate = 60
	animationRange = interval 0 (animLength-1)
	
	--Gather nodes
	local nodes = #()
	local nodecount = 0;
	for o in objects do
	(
		local indexProp = GetUserProp o "tag"
		if ( indexProp != undefined ) then
		(
			nodecount += 1;
			nodes[ nodecount ] = o
		)
	)
	
	
	--Apply to nodes
	with animate on
	(
		maxops.setDefaultTangentType #smooth #smooth
		for i = 1 to currentNode while i <= nodecount do 
		(
			xBox = box()
			yBox = box()
			zBox = box()
			for j = 1 to keyframes[i].count do
			(
				if keyFrames[i][j] != undefined then
				(
					at time (j - 1)
					(
						
						--Assign rotation keys
						if(keyFrames[i][j].XRot != undefined and keyFrames[i][j].YRot != undefined and keyFrames[i][j].ZRot != undefined) then
						(
							--nodes[i].Controller.Rotation = eulertoquat (eulerangles (keyFrames[i][j].XRot * (180/pi)) (keyFrames[i][j].YRot * (180/pi)) (keyFrames[i][j].ZRot * (180/pi)))
							
							addNewKey xBox.rotation.x_rotation.controller (j - 1)
							(getKeyAtTime xBox.rotation.x_rotation.controller (j - 1)).value = keyFrames[i][j].XRot * (180/pi)
							addNewKey yBox.rotation.y_rotation.controller (j - 1)
							(getKeyAtTime yBox.rotation.y_rotation.controller (j - 1)).value = keyFrames[i][j].YRot * (180/pi)
							addNewKey zBox.rotation.z_rotation.controller (j - 1)
							(getKeyAtTime zBox.rotation.z_rotation.controller (j - 1)).value = keyFrames[i][j].ZRot * (180/pi)
								
						) else
						(
							/*
							rot = (quattoeuler2 nodes[i].Controller.Rotation)
							if (keyFrames[i][j].XRot != undefined) then
							(
								rot.x = keyFrames[i][j].XRot * (180/pi)
							)
							if (keyFrames[i][j].YRot != undefined) then
							(
								rot.y = keyFrames[i][j].YRot * (180/pi)
							)
							if (keyFrames[i][j].ZRot != undefined) then
							(
								rot.z = keyFrames[i][j].ZRot * (180/pi)
							)
							nodes[i].Controller.Rotation = (eulertoquat rot)
							*/
							
							--rot = (quattoeuler2 nodes[i].Controller.Rotation)
							if (keyFrames[i][j].XRot != undefined) then
							(
								--rot.x = keyFrames[i][j].XRot * (180/pi)
								addNewKey xBox.rotation.x_rotation.controller (j - 1)
								(getKeyAtTime xBox.rotation.x_rotation.controller (j - 1)).value = keyFrames[i][j].XRot * (180/pi)
							)
							if (keyFrames[i][j].YRot != undefined) then
							(
								--rot.y = keyFrames[i][j].YRot * (180/pi)
								addNewKey yBox.rotation.y_rotation.controller (j - 1)
								(getKeyAtTime yBox.rotation.y_rotation.controller (j - 1)).value = keyFrames[i][j].YRot * (180/pi)
							)
							if (keyFrames[i][j].ZRot != undefined) then
							(
								--rot.z = keyFrames[i][j].ZRot * (180/pi)
								addNewKey zBox.rotation.z_rotation.controller (j - 1)
								(getKeyAtTime zBox.rotation.z_rotation.controller (j - 1)).value = keyFrames[i][j].ZRot * (180/pi)
							)
							--nodes[i].Controller.Rotation = (eulertoquat rot)
							
							--No matter the method, max makes keyframes for the other angles. Delete what we're not applying
							/*
							if (keyFrames[i][j].XRot == undefined) then
							(
								selectKeys nodes[i].rotation.x_rotation.controller (j - 1)
								deleteKeys nodes[i].rotation.x_rotation.controller.keys #selection
							)
							if (keyFrames[i][j].YRot == undefined) then
							(
								selectKeys nodes[i].rotation.y_rotation.controller (j - 1)
								deleteKeys nodes[i].rotation.y_rotation.controller.keys #selection
							)
							if (keyFrames[i][j].ZRot == undefined) then
							(
								selectKeys nodes[i].rotation.z_rotation.controller (j - 1)
								deleteKeys nodes[i].rotation.z_rotation.controller.keys #selection
							)*/
						)

						
					)
				)
			)
			
			
			--Loop again to set rotation interpolation and apply it to the node itself
			for j = 1 to keyframes[i].count do
			(
				if keyFrames[i][j] != undefined then
				(
					at time (j - 1)
					(
						if(keyFrames[i][j].XRot != undefined and keyFrames[i][j].YRot != undefined and keyFrames[i][j].ZRot != undefined) then
						(
							--Do nothing for now. If they're all assigned, they're good
						)
						else if(keyFrames[i][j].XRot != undefined or keyFrames[i][j].YRot != undefined or keyFrames[i][j].ZRot != undefined) then
						(
							addNewKey xBox.rotation.x_rotation.controller (j - 1)
							addNewKey yBox.rotation.y_rotation.controller (j - 1)
							addNewKey zBox.rotation.z_rotation.controller (j - 1)
							
							appendKey nodes[i].rotation.x_rotation.controller.keys (getKeyAtTime xBox.rotation.x_rotation.controller (j - 1))
							appendKey nodes[i].rotation.y_rotation.controller.keys (getKeyAtTime yBox.rotation.y_rotation.controller (j - 1))
							appendKey nodes[i].rotation.z_rotation.controller.keys (getKeyAtTime zBox.rotation.z_rotation.controller (j - 1))
							
							
							--nodes[i].Controller.Rotation = eulertoquat (eulerangles (getKeyAtTime xBox.rotation.x_rotation.controller (j - 1)).value (getKeyAtTime yBox.rotation.y_rotation.controller (j - 1)).value (getKeyAtTime zBox.rotation.z_rotation.controller (j - 1)).value)
						)
						
						--Rotation interpolation assignment
						/*
						xKey = getKeyAtTime nodes[i].rotation.x_rotation.controller (j - 1)
						if (xKey != undefined and keyFrames[i][j].XRot2 != undefined) then
						(
							xKey.inTangentType = #custom
							xKey.outTangentType = #custom
							xKey.inTangent = keyFrames[i][j].XRot2
							xKey.outTangent = keyFrames[i][j].XRot2
							xKey.outTangentLength = -1
							xKey.outTangentLength = 1
						)
						
						yKey = getKeyAtTime nodes[i].rotation.y_rotation.controller (j - 1)
						if (yKey != undefined and keyFrames[i][j].YRot2 != undefined) then
						(
							yKey.inTangentType = #custom
							yKey.outTangentType = #custom
							yKey.inTangent = keyFrames[i][j].YRot2
							yKey.outTangent = keyFrames[i][j].YRot2
							yKey.outTangentLength = -1
							yKey.outTangentLength = 1
						)
						
						zKey = getKeyAtTime nodes[i].rotation.z_rotation.controller (j - 1)
						if (zKey != undefined and keyFrames[i][j].ZRot2 != undefined) then
						(
							zKey.inTangentType = #custom
							zKey.outTangentType = #custom
							zKey.inTangent = keyFrames[i][j].ZRot2
							zKey.outTangent = keyFrames[i][j].ZRot2
							zKey.outTangentLength = -1
							zKey.outTangentLength = 1
						)*/
						
						--Fix rotations that go beyond 180
						/*
						xKey = getKeyAtTime nodes[i].rotation.x_rotation.controller (j - 1)
						if (xKey != undefined) then
						(
							xKeyVal = (getKeyAtTime nodes[i].rotation.x_rotation.controller (j - 1)).value
							while abs(xKeyVal) > 180 do
							(
								if xKeyVal > 0 then
								(
									xKeyVal -= 360 
								) else
								(
									xKeyVal += 360
								)
							)
							(getKeyAtTime nodes[i].rotation.x_rotation.controller (j - 1)).value = xKeyVal
						)
						
						yKey = getKeyAtTime yBox.rotation.y_rotation.controller (j - 1)
						if (yKey != undefined) then
						(
							yKeyVal = (getKeyAtTime yBox.rotation.y_rotation.controller (j - 1)).value
							while abs(yKeyVal) > 180 do
							(
								if yKeyVal > 0 then
								(
									yKeyVal -= 360 
								) else
								(
									yKeyVal += 360
								)
							)
							(getKeyAtTime yBox.rotation.y_rotation.controller (j - 1)).value = yKeyVal
						)
						
						zKey = getKeyAtTime zBox.rotation.z_rotation.controller (j - 1)
						if (zKey != undefined) then
						(
							zKeyVal = (getKeyAtTime zBox.rotation.z_rotation.controller (j - 1)).value
							while abs(zKeyVal) > 180 do
							(
								if zKeyVal > 0 then
								(
									zKeyVal -= 360 
								) else
								(
									zKeyVal += 360
								)
							)
							(getKeyAtTime zBox.rotation.z_rotation.controller (j - 1)).value = zKeyVal
						)*/
						
												
						--Assign translation keys
						if (keyFrames[i][j].XPos != undefined) then
						(
							nodes[i].Controller.Position.x = keyFrames[i][j].XPos
							
							xPKey = getKeyAtTime nodes[i].pos.x_position.controller (j - 1)
							
							if (xPKey != undefined and keyFrames[i][j].XPos2 != undefined) then
							(
								xPKey.inTangentType = #custom
								xPKey.outTangentType = #custom
								xPKey.inTangent = keyFrames[i][j].XPos2
								xPKey.outTangent = keyFrames[i][j].XPos2
								xPKey.outTangentLength = -1
								xPKey.outTangentLength = 1
							)
						)
						if (keyFrames[i][j].YPos != undefined) then
						(
							nodes[i].Controller.Position.y = keyFrames[i][j].YPos
							
							yPKey = getKeyAtTime nodes[i].pos.y_position.controller (j - 1)
							
							if (yPKey != undefined and keyFrames[i][j].YPos2 != undefined) then
							(
								yPKey.inTangentType = #custom
								yPKey.outTangentType = #custom
								yPKey.inTangent = keyFrames[i][j].YPos2
								yPKey.outTangent = keyFrames[i][j].YPos2
								yPKey.outTangentLength = -1
								yPKey.outTangentLength = 1
							)
						)
						if (keyFrames[i][j].ZPos != undefined) then
						(
							nodes[i].Controller.Position.z = keyFrames[i][j].ZPos
							
							zPKey = getKeyAtTime nodes[i].pos.z_position.controller (j - 1)
							if (zPKey != undefined and keyFrames[i][j].ZPos2 != undefined) then
							(
								zPKey.inTangentType = #custom
								zPKey.outTangentType = #custom
								zPKey.inTangent = keyFrames[i][j].ZPos2
								zPKey.outTangent = keyFrames[i][j].ZPos2
								zPKey.outTangentLength = -1
								zPKey.outTangentLength = 1
							)
						)
						
						--Delete unapplied keys
						if (keyFrames[i][j].XPos == undefined) then
						(
							selectKeys nodes[i].pos.x_position.controller (j - 1)
							deleteKeys nodes[i].pos.x_position.controller.keys #selection
						)
						if (keyFrames[i][j].YPos == undefined) then
						(
							selectKeys nodes[i].pos.y_position.controller (j - 1)
							deleteKeys nodes[i].pos.y_position.controller.keys #selection
						)
						if (keyFrames[i][j].ZPos == undefined) then
						(
							selectKeys nodes[i].pos.z_position.controller (j - 1)
							deleteKeys nodes[i].pos.z_position.controller.keys #selection
						)
						
						--Assign scale keys.... unfortunately cannot delete unused scaling keys
						if (keyFrames[i][j].XScale != undefined) then
						(
							nodes[i].Controller.Scale.x = keyFrames[i][j].XScale
						)
						if (keyFrames[i][j].YScale != undefined) then
						(
							nodes[i].Controller.Scale.y = keyFrames[i][j].YScale
						)
						if (keyFrames[i][j].ZScale != undefined) then
						(
							nodes[i].Controller.Scale.z = keyFrames[i][j].ZScale
						)
					)
					
				)
			)
			delete xBox
			delete yBox
			delete zBox
		)
	)
	
	
)

fn ExportMTN mtnFile =
(	
	cmp = floatCompressor()
	cmp.SetFile mtnFile bigEnd.checked
	cmp.MTNWrite()
	
	print "Export complete"
)

on importButton pressed do
(
	local objFileName = undefined
	-- Open up a dialog box
	objFileName = getOpenFileName caption:"Import Shadow The Hedgehog .STHANIM/MTN" \
				types:"Shadow The Hedgehog STHANIM/MTN (*.STHANIM,*.MTN)|*.STHANIM;*.MTN|All Files (*.*)|*.*|"
	
	if objFileName != undefined then
	(
		ClearListener()
		print (filenameFromPath objFileName)
		
		if oldImp.checked == true then
		(
			SkelImport0 objFileName 
		) else
		(
			SkelImport objFileName 
		)
	)
	
	-- Redraw max viewports
	max views redraw
	-- Ta-daa! You should now see a lovely new imported model in all its glory.
	--print "Import completed."
)

on ExportButton pressed do
(
	-- Open up a dialog box
	local objFileName = getSaveFileName "Export Shadow The Hedgehog .STHANIM/MTN" \
			types:"Shadow the Hedgehog MTN (*.MTN)|*.MTN|Shadow the Hedgehog STHANIM (*.STHANIM)|*.STHANIM|All Files (*.*)|*.*|"

	--Export the Animation 
	if (objFileName != undefined) then
	(
		ExportMTN objFileName
	)
)

)
createDialog bonImport 200 320