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
	checkBox autoSizeCheckBox "Rescale" checked:false align:#center
	spinner autoSizeSpinner "Scale by:" align:#center type:#float range:[0,10000,100] enabled:false
	checkBox YZCheckBox "Y-Z Axis Flip" checked:false align:#center
)	
group "Import"
(
	button importButton "Import..."
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
	
	reader.SeekSet( 0xA)
	nodeCount = reader.ReadU16()
	rootOffset = reader.ReadF32()
	charID = reader.ReadFixedLengthString 0x20
	
	--Read bones
	for i = 1 to nodeCount do
	(
		boneTag = reader.ReadU32()
		boneUnkInt = reader.ReadF32() --Always 0??
		boneShort = reader.ReadU16() -- Always 0??
		boneSplitID = reader.ReadU8()
		boneParamID = reader.ReadU8()
		reader.SeekCur( 0x04 ) --NullZero
		PosVec = reader.ReadVec3F32(); reader.ReadF32()
		RotVec = reader.ReadVec3F32(); reader.ReadF32(); RotVec.x *= (180/pi); RotVec.y *= (180/pi); RotVec.z *= (180/pi);
		ScaleVec = reader.ReadVec3F32(); reader.ReadF32()
		reader.SeekCur( 0x08 ) --NullZero
		parInt = bit.intAsHex (reader.ReadU32())
		sibInt = bit.intAsHex (reader.ReadU32())
		boneName = reader.ReadFixedLengthString 0x20
		
		print ("i: " + (i as string) + " Tag: " + (boneTag as string) + " Float: " + (BoneUnkInt as string) + " BoneShort: " + (boneShort as string) + " SplitID: " + (boneSplitID as string) + " ParamID: " + (boneParamID as string))
		--print (" Pos: " + (PosVec as string) + " Rot: " + (RotVec as string) + " Scale: " + (ScaleVec as string))
		--print ("Tag: " + (boneTag as string) + " ParInt: " + (parInt) + " SibInt: " + (sibInt) + " BoneName: " + (boneName))
		
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
			
			if(PRSChecked) then
			(
				local newBone = bonesys.createbone \
					  tfm.row4 \
					  (tfm.row4 + 0.01 * (normalize tfm.row1)) \
					  (normalize tfm.row3);		
			) else (
				local newBone = bonesys.createbone \
					  tfm.row4 \
					  (tfm.row4 + 0.01 * (normalize tfm.row3)) \
					  (normalize tfm.row1);		
			)

							  
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
		
		--Create extra nodes in max
		for node in ExtraDataArray do
		(
			tfm = (eulerangles node.BonePRSRotation.x node.BonePRSRotation.y node.BonePRSRotation.z) as matrix3
			--tfm *= ScaleMatrix node.BonePRSScale
			tfm.row4 = node.BonePRSPosition
			
			if ( node.BoneParent != -1) do
			(
				maxParent = BoneDataArray[node.BoneParent+1].MaxBone	
				tfm *= maxParent.Transform
			)
			
			local newBone = bonesys.createbone \
					  tfm.row4 \
					  (tfm.row4 + 0.01 * (normalize tfm.row3)) \
					  (normalize tfm.row1);
							  
			newBone.name = node.BoneName;
			newBone.width  = 0.05;
			newBone.height = 0.05;
			newBone.transform = tfm;
			newBone.setBoneEnable false 0;
			newBone.wirecolor = ([0,128,128] as color);
			newBone.showlinks = false;
			newBone.pos.controller      = TCB_position ();
			newBone.rotation.controller = TCB_rotation ();
			newBone.Parent = maxParent;
			
		)
		*/
	)
)

on autoSizeCheckBox changed nowChecked do
(
	autoSizeSpinner.enabled = nowChecked
)

on importButton pressed do
(
	local objFileName = undefined
	-- Open up a dialog box
	objFileName = getOpenFileName caption:"Import Shadow The Hedgehog .BON" \
				types:"Shadow The Hedgehog Skeleton BON (*.BON)|*.BON|All Files (*.*)|*.*|"
	if (objFileName != undefined) then
	(
		SkelImport objFileName
	)
	
	-- Redraw max viewports
	max views redraw
	-- Ta-daa! You should now see a lovely new imported model in all its glory.
	--print "Import completed."
)

)
createDialog bonImport 160 320