/*
	Shadow the Hedgehog .BON import

	-Huge Thanks to TGE for function(s) from other scripts
	
*/
ClearListener()
FileIn @"include\MaxScriptExtensions\FileStreamReader.ms"
FileIn @"include\MaxScriptExtensions\FileUtils.ms"

rollout bonImport ".BON Importer"
(
--------------------
-- User Interface --
--------------------
group "About"
(
	label lab1 "Shadow TH .BON  Importer"
	Label lab2 "By Shadowth117"
)
group "Settings"
(
	checkBox hApply "Apply to hierarchy" checked:true align:#center
	--checkBox autoSizeCheckBox "Rescale" checked:false align:#center
	/*
	spinner autoSizeSpinner "Scale by:" align:#center type:#float range:[0,10000,100] enabled:false
	checkBox YZCheckBox "Y-Z Axis Flip" checked:false align:#center*/
)	
group "Import"
(
	button importButton "Import..."
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
	shBON,
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
		shBON
	),
	
	public fn SetFile aFilePath aIsBigEndian = 
	(
		bigEndian = aIsBigEndian
		shBON = FOpen aFilePath "wb"
	),
	
	public fn Close =
	(
		FFlush shBON
		FClose shBON
		shBON = undefined
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
		WriteShort shBON U16
	),
	
	fn WriteU32 U32 =
	(
		U32W = U32
		if bigEndian == true then
		(
			U32W = (Bit.SwapBytes (Bit.SwapBytes (U32W) 1 4) 2 3)
		)
		WriteLong shBON U32W
		
	),
	
	fn WriteF16 f32float =
	(
		if (FloatCompare f32float 0 0.00001) == true then
		(
			WriteShort shBON 0
		) else 
		(
			f32 = bit.floatAsInt f32float
			f16 = basetable[bit.and (bit.shift f32 -23) 0x1ff]+(bit.shift (bit.and f32 0x007fffff) -(shifttable[bit.and (bit.shift f32 -23) 0x1ff]))

			if bigEndian == true then
			(
				f16 = Bit.SwapBytes f16 1 2
				WriteShort shBON f16
			) else
			(
				WriteShort shBON f16
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
		WriteLong shBON F32W
		
	),
	
	fn BONWrite = 
	(
		firstChildAdd = #()
		sibAdd = #()
		objList = for o in (objects) where ((GetUserProp o "tag") != undefined) collect o
		
		WriteByte shBON 4 -- 0x4
		WriteByte shBON 1 -- endianness, 0 for little, 1 for big
		fseek shBON 0x6 #seek_cur
		WriteU16 0xFF -- U16 Short
		WriteU16 objList.count --nodeCount, 1 based
		WriteF32 objList[2].pos.y --second node y value

		charName = (substring anmName.text 1 0x20)
		extraSpace = 0x20 - (charName.count) --calculate space left to 20 (if any)
		WriteString shBON charName --0x20 string for animation id (ex. sh for shadow)
		fseek shBON (-1) #seek_cur
		for e = 1 to extraSpace do -- add padding to reach 0x20 if needed
		(
			writeByte shBON 0x0
		)
		
		
		
		for i = 1 to objList.count  do
		(
			o = objList[i]
			SetUserProp o "Address" (ftell shBON)
			WriteU32 (GetUserProp o "tag")
			if i == 1 then
			(
				WriteU16 1
				WriteU16 0x3BF
			) else
			(
				WriteU16 0
				WriteU16 0x7BF
			)
			WriteU16 0
			splitByte = (GetUserProp o "SplitID")
			if splitByte == undefined then
			(
				if autoCalcSplit == true then
				(
					if o.x > splitVal then
					(
						splitByte = 64
					) else if o.x < -splitVal then
					(
						splitByte = 128
					) else
					(
						splitByte = 0
					)
				)
			)
			bitbyte = (GetUserProp o "ParamID")
			if bigEndian == true then
			(
				if splitByte == undefined then
				(
					WriteByte shBON 0
				) else
				(
					WriteByte shBON splitByte
				)
				if bitByte == undefined then
				(
					WriteByte shBON 0x31
				) else
				(
					WriteByte shBON bitByte
				)
			)
			else
			(
				if bitByte == undefined then
				(
					WriteByte shBON 0x31
				) else
				(
					WriteByte shBON bitByte
				)
				if splitByte == undefined then
				(
					WriteByte shBON 0
				) else
				(
					WriteByte shBON splitByte
				)
			)
			WriteU32 0
			relPos = RelativePosition o 0
			WriteF32 relPos.translationpart.x
			WriteF32 relPos.translationpart.y
			WriteF32 relPos.translationpart.z
			WriteU32 0
			eulerRot = (quattoeuler o.transform.rotationpart)
			WriteF32 (eulerRot.x * pi/180)
			WriteF32 (eulerRot.y * pi/180)
			WriteF32 (eulerRot.z * pi/180)
			WriteU32 0
			WriteF32 o.scale.x
			WriteF32 o.scale.y
			WriteF32 o.scale.z
			WriteU32 0
			WriteU32 0
			WriteU32 0
			firstAdd = ftell shBON
			WriteU32 0
			nextSibAdd = ftell shBON
			WriteU32 0
			
			charName = (substring o.name 1 0x20)
			extraSpace = 0x20 - (charName.count) --calculate space left to 20 (if any)
			WriteString shBON charName --0x20 string for animation id (ex. sh for shadow)
			fseek shBON (-1) #seek_cur
			for e = 1 to extraSpace do -- add padding to reach 0x20 if needed
			(
				writeByte shBON 0x0
			)
			
			append firstChildAdd firstAdd
			append sibAdd nextSibAdd
		)

		--Loop back through and fill in address info
		for i = 1 to objList.count do
		(
			o = objList[i]
			
			boneFirstChild = undefined
			if (o.children.count != 0 ) then
			( 
				if(((getUserProp o.children[1] "tag") != undefined)) then --Make sure we care about this node
				(
					boneFirstChild = o.children[1]
				)
				else
				(
					boneFirstChild = undefined
				)
			)
			else
			(
				boneFirstChild = undefined
			)
			if boneFirstChild != undefined then
			(
				fseek shBON firstChildAdd[i] #seek_set
				WriteU32 ((getUserProp boneFirstChild "Address") as integer)
			)
			
			boneNextSibling = undefined
			--Find  the node's next sibling by order
			if(o.parent != undefined) then
			(
				rootBackup = o
				parentChildren = o.parent.children
				if (parentChildren.count > 1 and parentChildren[parentChildren.count] != o) then
				(
					nextChild = false
					for i = 1 to parentChildren.count do
					(
						if(nextChild == true) then
						(
							if((getUserProp parentChildren[i] "tag") != undefined) then --Make sure it's an object we want
							(
								boneNextSibling = parentChildren[i]
								nextChild = false
							)
						) else if parentChildren[i] == o then
						(
							nextChild = true
						)
					)
				)
			)	
			else 
			(
				boneNextSibling = undefined
			)
			if boneNextSibling != undefined then
			(
				fseek shBON sibAdd[i] #seek_set
				WriteU32 ((getUserProp boneNextSibling "Address") as integer)
			)
		)
		
		FFlush shBON
		FClose shBON
	)
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

fn SkelImport aqnFile =
(
	-- Read file
	local reader = FileStreamReader()
	reader.SetFile aqnFile false
	reader.SetBigEndian true
	
	BoneTagArray = #()
	BoneDataArray = #()
	
	reader.ReadU8()
	endian = reader.ReadU8()
	if endian == 0 then
	(
		reader.SetBigEndian false
	)
	reader.SeekCur( 0x8)
	nodeCount = reader.ReadU16()
	rootOffset = reader.ReadF32()
	charID = reader.ReadFixedLengthString 0x20
	
	--Read bones
	for i = 1 to nodeCount do
	(
		boneTag = reader.ReadU32()
		BoneFlag = reader.ReadU16()  --Always 1 for first in file?
		boneUnkInt = reader.ReadF16() --Always 0??
		boneShort = reader.ReadU16() -- Always 0??
		boneSplitID = reader.ReadU8()
		boneParamID = reader.ReadU8()
		reader.SeekCur( 0x04 ) --NullZero
		PosVec = reader.ReadVec3F32(); reader.ReadF32()
		RotVec = reader.ReadVec3F32(); reader.ReadF32(); RotVec.x *= (180/pi); RotVec.y *= (180/pi); RotVec.z *= (180/pi);
		ScaleVec = reader.ReadVec3F32(); reader.ReadF32()
		reader.SeekCur( 0x08 ) --NullZero
		parInt = bit.intAsHex (reader.ReadU32()) --First Child Address
		sibInt = bit.intAsHex (reader.ReadU32())
		boneName = reader.ReadFixedLengthString 0x20
		
		--print ("i: " + (i as string) + " Flag: " + (boneFlag as string) + " F16: " + (BoneUnkInt as string) + " BoneShort: " + (boneShort as string) + " SplitID: " + (boneSplitID as string) + " ParamID: " + (boneParamID as string) + " BoneName:" + (boneName))
		--print (" Pos: " + (PosVec as string) + " Rot: " + (RotVec as string) + " Scale: " + (ScaleVec as string))
		--print ("Tag: " + (boneTag as string) + " FirstChild Address " + (parInt) + " SibInt: " + (sibInt) + " BoneName: " + (boneName))
		
		append BoneTagArray boneTag
		append BoneDataArray (BoneStruct BoneOrder:(i-1) BoneTag:boneTag BoneUnkInt:boneUnkInt BoneShort:boneShort BoneSplitID:boneSplitID BoneParamID:boneParamID BoneParent:undefined ParInt:parInt SibInt:sibInt BoneName:boneName BonePRSPosition:PosVec BonePRSRotation:RotVec BonePRSScale:ScaleVec)
	)
	
	if hApply.checked then
	(
		--Adjust bones
		for o in objects do
		(
			item = getUserProp o "tag"
			if(item != undefined) then
			(
				ID = finditem BoneTagArray item
				if (ID != undefined) then
				(
					o.name = BoneDataArray[ID].BoneName
					setUserProp o "SplitID" BoneDataArray[ID].BoneSplitID
					setUserProp o "ParamID" BoneDataArray[ID].BoneParamID
				)
			)
		)
	) else
	(
		/*
		--Create bones in max
		for node in BoneDataArray do
		(
			local parentBone = undefined;
			if ( node.BoneParent != -1 ) do
				parentBone = BoneDataArray[node.BoneParent+1].MaxBone;
			
			if (PRSChecked) then
			(
				tfm = (eulerangles node.BonePRSRotation.x -node.BonePRSRotation.y node.BonePRSRotation.z) as matrix3
				tfm *= ScaleMatrix node.BonePRSScale
				tfm.row4 = node.BonePRSPosition
			) else (
				 tfm = (inverse node.BoneTFM);
			)
			
			--local tfm = (inverse node.BoneTFM);
			if ( parentBone != undefined and PRSChecked) do
				tfm *= parentBone.Transform;
			

			local newBone = bonesys.createbone \
				  tfm.row4 \
				  (tfm.row4 + 0.01 * (normalize tfm.row3)) \
				  (normalize tfm.row1);		

							  
			newBone.name = node.BoneName;
			newBone.width  = 0.001;
			newBone.height = 0.001;
			newBone.transform = tfm;
			newBone.setBoneEnable false 0;
			newBone.wirecolor = ([0,128,128] as color);
			newBone.showlinks = true;
			newBone.pos.controller      = TCB_position ();
			newBone.rotation.controller = TCB_rotation ();
			newBone.Parent = parentBone;
			
			node.MaxBone = newBone; 
		)
		*/
	)
)

fn SkelExport bonFile =
(
	cmp = floatCompressor()
	cmp.SetFile bonFile bigEnd.checked
	cmp.BONWrite()
	
	print "Export complete"
)

/*
on autoSizeCheckBox changed nowChecked do
(
	autoSizeSpinner.enabled = nowChecked
)*/

on importButton pressed do
(
	local objFileName = undefined
	-- Open up a dialog box
	objFileName = getOpenFileName caption:"Import Shadow The Hedgehog .BON" \
				types:"Shadow The Hedgehog Skeleton BON (*.BON)|*.BON|All Files (*.*)|*.*|"
	if (objFileName != undefined) then
	(
		ClearListener()
		print (filenameFromPath objFileName)
		SkelImport objFileName
	)
	
	-- Redraw max viewports
	max views redraw
	-- Ta-daa! You should now see a lovely new imported model in all its glory.
	--print "Import completed."
)

on ExportButton pressed do
(
	-- Open up a dialog box
	local objFileName = getSaveFileName "Export Shadow The Hedgehog .BON" \
			types:"Shadow The Hedgehog Skeleton BON (*.BON)|*.BON|All Files (*.*)|*.*|"

	--Export the Animation 
	if (objFileName != undefined) then
	(
		SkelExport objFileName
	)
)

)
createDialog bonImport 160 320