/****************************************************************************
 *
 * (c) 2009-2020 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

import QtQuick          2.3
import QtQuick.Controls 2.15
import QtQuick.Dialogs  1.2
import QtLocation       5.3
import QtPositioning    5.3
import QtQuick.Layouts  1.2
import QtQuick.Window   2.2
import QtGraphicalEffects 1.12

import QGroundControl                   1.0
import QGroundControl.FlightMap         1.0
import QGroundControl.ScreenTools       1.0
import QGroundControl.Controls          1.0
import QGroundControl.FactSystem        1.0
import QGroundControl.FactControls      1.0
import QGroundControl.Palette           1.0
import QGroundControl.Controllers       1.0
import QGroundControl.ShapeFileHelper   1.0
import QGroundControl.Airspace          1.0
import QGroundControl.Airmap            1.0

Item {
    id: _root

    property bool planControlColapsed: false

    readonly property int   _decimalPlaces:             8
    readonly property real  _margin:                    ScreenTools.defaultFontPixelHeight * 0.5
    readonly property real  _toolsMargin:               ScreenTools.defaultFontPixelWidth * 0.75
    readonly property real  _radius:                    ScreenTools.defaultFontPixelWidth  * 0.5
    readonly property real  _rightPanelWidth:           Math.min(parent.width / 3, ScreenTools.defaultFontPixelWidth * 30)
    readonly property var   _defaultVehicleCoordinate:  QtPositioning.coordinate(37.803784, -122.462276)
    readonly property bool  _waypointsOnlyMode:         QGroundControl.corePlugin.options.missionWaypointsOnly

    property bool   _airspaceEnabled:                    QGroundControl.airmapSupported ? (QGroundControl.settingsManager.airMapSettings.enableAirMap.rawValue && QGroundControl.airspaceManager.connected): false
    property var    _missionController:                 _planMasterController.missionController
    property var    _geoFenceController:                _planMasterController.geoFenceController
    property var    _rallyPointController:              _planMasterController.rallyPointController
    property var    _visualItems:                       _missionController.visualItems
    property bool   _lightWidgetBorders:                editorMap.isSatelliteMap
    property bool   _addROIOnClick:                     false
    property bool   _singleComplexItem:                 _missionController.complexMissionItemNames.length === 1
    property int    _editingLayer:                      layerTabBar.currentIndex ? _layers[layerTabBar.currentIndex] : _layerMission
    property int    _toolStripBottom:                   toolStrip.height + toolStrip.y
    property var    _appSettings:                       QGroundControl.settingsManager.appSettings
    property var    _planViewSettings:                  QGroundControl.settingsManager.planViewSettings
    property bool   _promptForPlanUsageShowing:         false

    readonly property var       _layers:                [_layerMission, _layerGeoFence, _layerRallyPoints]

    readonly property int       _layerMission:              1
    readonly property int       _layerGeoFence:             2
    readonly property int       _layerRallyPoints:          3
    readonly property string    _armedVehicleUploadPrompt:  qsTr("Vehicle is currently armed. Do you want to upload the mission to the vehicle?")

    function mapCenter() {
        var coordinate = editorMap.center
        coordinate.latitude  = coordinate.latitude.toFixed(_decimalPlaces)
        coordinate.longitude = coordinate.longitude.toFixed(_decimalPlaces)
        coordinate.altitude  = coordinate.altitude.toFixed(_decimalPlaces)
        return coordinate
    }

    function updateAirspace(reset) {
        if(_airspaceEnabled) {
            var coordinateNW = editorMap.toCoordinate(Qt.point(0,0), false /* clipToViewPort */)
            var coordinateSE = editorMap.toCoordinate(Qt.point(width,height), false /* clipToViewPort */)
            if(coordinateNW.isValid && coordinateSE.isValid) {
                QGroundControl.airspaceManager.setROI(coordinateNW, coordinateSE, true /*planView*/, reset)
            }
        }
    }

    property bool _firstMissionLoadComplete:    false
    property bool _firstFenceLoadComplete:      false
    property bool _firstRallyLoadComplete:      false
    property bool _firstLoadComplete:           false
    property var presetModelDefault :[
        { text: qsTr("Current Location"),coordinate: globals.activeVehicle?QtPositioning.coordinate(globals.activeVehicle.coordinate.latitude,globals.activeVehicle.coordinate.longitude,20):QtPositioning.coordinate() },
        { text: qsTr("RangeAero Office"), coordinate: QtPositioning.coordinate(13.0436028,77.5773236,20) },
        { text: qsTr("Peacock layout"), coordinate: QtPositioning.coordinate(13.0472723,77.4711951,25) },
    ]
    property var presetModelSession :{
        "A":null,
        "B":null
    }
    property var presetABType: [
        {"index":1,"preset":null},
        {"index":2,"preset":null}
    ]
    property var presetModels: [
        null,
        presetABType,
    ]
    property var presetContainers: [

    ]
    property var selectedContainer:null

    enum PresetType {
        TypeNone,
        TypeAB,
        TypeABA,
        TypeABC,
        TypeAZ
    }

    property var session: {
        "model":presetABType
    }

    MapFitFunctions {
        id:                         mapFitFunctions  // The name for this id cannot be changed without breaking references outside of this code. Beware!
        map:                        editorMap
        usePlannedHomePosition:     true
        planMasterController:       _planMasterController
    }

    on_AirspaceEnabledChanged: {
        if(QGroundControl.airmapSupported) {
            if(_airspaceEnabled) {
                planControlColapsed = QGroundControl.airspaceManager.airspaceVisible
                updateAirspace(true)
            } else {
                planControlColapsed = false
            }
        } else {
            planControlColapsed = false
        }
    }

    onVisibleChanged: {
        if(visible) {
            editorMap.zoomLevel = QGroundControl.flightMapZoom
            editorMap.center    = QGroundControl.flightMapPosition
//            if (!_planMasterController.containsItems) {
                toolStrip.simulateClick(toolStrip.presetButtonIndex)
                globals.toolSelectMode = true
//            }
        }
    }

    Connections {
        target: _appSettings ? _appSettings.defaultMissionItemAltitude : null
        function onRawValueChanged() {
            if (_visualItems.count > 1) {
                mainWindow.showComponentDialog(applyNewAltitude, qsTr("Apply new altitude"), mainWindow.showDialogDefaultWidth, StandardButton.Yes | StandardButton.No)
            }
        }
    }

    Component {
        id: applyNewAltitude
        QGCViewMessage {
            message:    qsTr("You have changed the default altitude for mission items. Would you like to apply that altitude to all the items in the current mission?")
            function accept() {
                hideDialog()
                _missionController.applyDefaultMissionAltitude()
            }
        }
    }

    Component {
        id: promptForPlanUsageOnVehicleChangePopupComponent
        QGCPopupDialog {
            title:      _planMasterController.managerVehicle.isOfflineEditingVehicle ? qsTr("Plan View - Vehicle Disconnected") : qsTr("Plan View - Vehicle Changed")
            buttons:    StandardButton.NoButton

            ColumnLayout {
                QGCLabel {
                    Layout.maximumWidth:    parent.width
                    wrapMode:               QGCLabel.WordWrap
                    text:                   _planMasterController.managerVehicle.isOfflineEditingVehicle ?
                                                qsTr("The vehicle associated with the plan in the Plan View is no longer available. What would you like to do with that plan?") :
                                                qsTr("The plan being worked on in the Plan View is not from the current vehicle. What would you like to do with that plan?")
                }

                QGCButton {
                    Layout.fillWidth:   true
                    text:               _planMasterController.dirty ?
                                            (_planMasterController.managerVehicle.isOfflineEditingVehicle ?
                                                 qsTr("Discard Unsaved Changes") :
                                                 qsTr("Discard Unsaved Changes, Load New Plan From Vehicle")) :
                                            qsTr("Load New Plan From Vehicle")
                    onClicked: {
                        _planMasterController.showPlanFromManagerVehicle()
                        _promptForPlanUsageShowing = false
                        hideDialog();
                    }
                }

                QGCButton {
                    Layout.fillWidth:   true
                    text:               _planMasterController.managerVehicle.isOfflineEditingVehicle ?
                                            qsTr("Keep Current Plan") :
                                            qsTr("Keep Current Plan, Don't Update From Vehicle")
                    onClicked: {
                        if (!_planMasterController.managerVehicle.isOfflineEditingVehicle) {
                            _planMasterController.dirty = true
                        }
                        _promptForPlanUsageShowing = false
                        hideDialog()
                    }
                }
            }
        }
    }


    Component {
        id: firmwareOrVehicleMismatchUploadDialogComponent
        QGCViewMessage {
            message: qsTr("This Plan was created for a different firmware or vehicle type than the firmware/vehicle type of vehicle you are uploading to. " +
                            "This can lead to errors or incorrect behavior. " +
                            "It is recommended to recreate the Plan for the correct firmware/vehicle type.\n\n" +
                            "Click 'Ok' to upload the Plan anyway.")

            function accept() {
                _planMasterController.sendToVehicle()
                hideDialog()
            }
        }
    }

    Connections {
        target: QGroundControl.airspaceManager
        function onAirspaceVisibleChanged() {
            planControlColapsed = QGroundControl.airspaceManager.airspaceVisible
        }
    }

    Component {
        id: noItemForKML
        QGCViewMessage {
            message:    qsTr("You need at least one item to create a KML.")
        }
    }

    PlanMasterController {
        id:         _planMasterController
        flyView:    false

        Component.onCompleted: {
            _planMasterController.start()
            _missionController.setCurrentPlanViewSeqNum(0, true)
            globals.planMasterControllerPlanView = _planMasterController
        }

        onPromptForPlanUsageOnVehicleChange: {
            if (!_promptForPlanUsageShowing) {
                _promptForPlanUsageShowing = true
                mainWindow.showPopupDialogFromComponent(promptForPlanUsageOnVehicleChangePopupComponent)
            }
        }

        function waitingOnIncompleteDataMessage(save) {
            var saveOrUpload = save ? qsTr("Save") : qsTr("Upload")
            mainWindow.showMessageDialog(qsTr("Unable to %1").arg(saveOrUpload), qsTr("Plan has incomplete items. Complete all items and %1 again.").arg(saveOrUpload))
        }

        function waitingOnTerrainDataMessage(save) {
            var saveOrUpload = save ? qsTr("Save") : qsTr("Upload")
            mainWindow.showMessageDialog(qsTr("Unable to %1").arg(saveOrUpload), qsTr("Plan is waiting on terrain data from server for correct altitude values."))
        }

        function checkReadyForSaveUpload(save) {
            if (readyForSaveState() == VisualMissionItem.NotReadyForSaveData) {
                waitingOnIncompleteDataMessage(save)
                return false
            } else if (readyForSaveState() == VisualMissionItem.NotReadyForSaveTerrain) {
                waitingOnTerrainDataMessage(save)
                return false
            }
            return true
        }

        function upload() {
            if (!checkReadyForSaveUpload(false /* save */)) {
                return
            }
            switch (_missionController.sendToVehiclePreCheck()) {
                case MissionController.SendToVehiclePreCheckStateOk:
                    sendToVehicle()
                    break
                case MissionController.SendToVehiclePreCheckStateActiveMission:
                    mainWindow.showMessageDialog(qsTr("Send To Vehicle"), qsTr("Current mission must be paused prior to uploading a new Plan"))
                    break
                case MissionController.SendToVehiclePreCheckStateFirwmareVehicleMismatch:
                    mainWindow.showComponentDialog(firmwareOrVehicleMismatchUploadDialogComponent, qsTr("Plan Upload"), mainWindow.showDialogDefaultWidth, StandardButton.Ok | StandardButton.Cancel)
                    break
            }
        }

        function loadFromSelectedFile() {
            fileDialog.title =          qsTr("Select Plan File")
            fileDialog.planFiles =      true
            fileDialog.selectExisting = true
            fileDialog.nameFilters =    _planMasterController.loadNameFilters
            fileDialog.openForLoad()
        }

        function saveToSelectedFile() {
            if (!checkReadyForSaveUpload(true /* save */)) {
                return
            }
            fileDialog.title =          qsTr("Save Plan")
            fileDialog.planFiles =      true
            fileDialog.selectExisting = false
            fileDialog.nameFilters =    _planMasterController.saveNameFilters
            fileDialog.openForSave()
        }

        function fitViewportToItems() {
            mapFitFunctions.fitMapViewportToMissionItems()
        }

        function saveKmlToSelectedFile() {
            if (!checkReadyForSaveUpload(true /* save */)) {
                return
            }
            fileDialog.title =          qsTr("Save KML")
            fileDialog.planFiles =      false
            fileDialog.selectExisting = false
            fileDialog.nameFilters =    ShapeFileHelper.fileDialogKMLFilters
            fileDialog.openForSave()
        }
    }

    Connections {
        target: _missionController

        function onNewItemsFromVehicle() {
            if (_visualItems && _visualItems.count !== 1) {
                mapFitFunctions.fitMapViewportToMissionItems()
            }
            _missionController.setCurrentPlanViewSeqNum(0, true)
        }
    }

    function insertSimpleItemAfterCurrent(coordinate) {
        var nextIndex = _missionController.currentPlanViewVIIndex + 1
        _missionController.insertSimpleMissionItem(coordinate, nextIndex, true /* makeCurrentItem */)
    }

    function insertROIAfterCurrent(coordinate) {
        var nextIndex = _missionController.currentPlanViewVIIndex + 1
        _missionController.insertROIMissionItem(coordinate, nextIndex, true /* makeCurrentItem */)
    }

    function insertCancelROIAfterCurrent() {
        var nextIndex = _missionController.currentPlanViewVIIndex + 1
        _missionController.insertCancelROIMissionItem(nextIndex, true /* makeCurrentItem */)
    }

    function insertComplexItemAfterCurrent(complexItemName) {
        var nextIndex = _missionController.currentPlanViewVIIndex + 1
        _missionController.insertComplexMissionItem(complexItemName, mapCenter(), nextIndex, true /* makeCurrentItem */)
    }

    function insertTakeItemAfterCurrent() {
        var nextIndex = _missionController.currentPlanViewVIIndex + 1
        _missionController.insertTakeoffItem(mapCenter(), nextIndex, true /* makeCurrentItem */)
    }

    function insertLandItemAfterCurrent() {
        var nextIndex = _missionController.currentPlanViewVIIndex + 1
        _missionController.insertLandItem(mapCenter(), nextIndex, true /* makeCurrentItem */)
    }


    function selectNextNotReady() {
        var foundCurrent = false
        for (var i=0; i<_missionController.visualItems.count; i++) {
            var vmi = _missionController.visualItems.get(i)
            if (vmi.readyForSaveState === VisualMissionItem.NotReadyForSaveData) {
                _missionController.setCurrentPlanViewSeqNum(vmi.sequenceNumber, true)
                break
            }
        }
    }

    property int _moveDialogMissionItemIndex

    QGCFileDialog {
        id:             fileDialog
        folder:         _appSettings ? _appSettings.missionSavePath : ""

        property bool planFiles: true    ///< true: working with plan files, false: working with kml file

        onAcceptedForSave: {
            if (planFiles) {
                _planMasterController.saveToFile(file)
            } else {
                _planMasterController.saveToKml(file)
            }
            close()
        }

        onAcceptedForLoad: {
            _planMasterController.loadFromFile(file)
            _planMasterController.fitViewportToItems()
            _missionController.setCurrentPlanViewSeqNum(0, true)
            close()
        }
    }

    Component {
        id: moveDialog
        QGCViewDialog {
            function accept() {
                var toIndex = toCombo.currentIndex
                if (toIndex === 0) {
                    toIndex = 1
                }
                _missionController.moveMissionItem(_moveDialogMissionItemIndex, toIndex)
                hideDialog()
            }
            Column {
                anchors.left:   parent.left
                anchors.right:  parent.right
                spacing:        ScreenTools.defaultFontPixelHeight

                QGCLabel {
                    anchors.left:   parent.left
                    anchors.right:  parent.right
                    wrapMode:       Text.WordWrap
                    text:           qsTr("Move the selected mission item to the be after following mission item:")
                }

                QGCComboBox {
                    id:             toCombo
                    model:          _visualItems.count
                    currentIndex:   _moveDialogMissionItemIndex
                }
            }
        }
    }

    Item {
        id:             panel
        anchors.fill:   parent

        FlightMap {
            id:                         editorMap
            anchors.fill:               parent
            mapName:                    "MissionEditor"
            allowGCSLocationCenter:     true
            allowVehicleLocationCenter: true
            planView:                   true //&& !globals.toolSelectMode

            zoomLevel:                  QGroundControl.flightMapZoom
            center:                     QGroundControl.flightMapPosition

            // This is the center rectangle of the map which is not obscured by tools
            property rect centerViewport:   Qt.rect(_leftToolWidth + _margin,  _margin, editorMap.width - _leftToolWidth - _rightToolWidth - (_margin * 2), (terrainStatus.visible ? terrainStatus.y : height - _margin) - _margin)

            property real _leftToolWidth:       toolStrip.x + toolStrip.width
            property real _rightToolWidth:      rightPanel.width + rightPanel.anchors.rightMargin
            property real _nonInteractiveOpacity:  0.5

            // Initial map position duplicates Fly view position
            Component.onCompleted: editorMap.center = QGroundControl.flightMapPosition

            QGCMapPalette { id: mapPal; lightColors: editorMap.isSatelliteMap }

            onZoomLevelChanged: {
                QGroundControl.flightMapZoom = zoomLevel
                updateAirspace(false)
            }
            onCenterChanged: {
                QGroundControl.flightMapPosition = center
                updateAirspace(false)
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    // Take focus to close any previous editing
                    editorMap.focus = true
                    var coordinate = editorMap.toCoordinate(Qt.point(mouse.x, mouse.y), false /* clipToViewPort */)
                    coordinate.latitude = coordinate.latitude.toFixed(_decimalPlaces)
                    coordinate.longitude = coordinate.longitude.toFixed(_decimalPlaces)
                    coordinate.altitude = coordinate.altitude.toFixed(_decimalPlaces)

                    switch (_editingLayer) {
                    case _layerMission:
                        if (addWaypointRallyPointAction.checked) {
                            insertSimpleItemAfterCurrent(coordinate)
                        } else if (_addROIOnClick) {
                            insertROIAfterCurrent(coordinate)
                            _addROIOnClick = false
                        }

                        break
                    case _layerRallyPoints:
                        if (_rallyPointController.supported && addWaypointRallyPointAction.checked) {
                            _rallyPointController.addPoint(coordinate)
                        }
                        break
                    }
                }
            }

            // Add the mission item visuals to the map
            Repeater {
                model: _missionController.visualItems
                delegate: MissionItemMapVisual {
                    map:         editorMap
                    onClicked:   {_missionController.setCurrentPlanViewSeqNum(sequenceNumber, false);}
                    onDoubleClicked:   {_missionController.setCurrentPlanViewSeqNum(sequenceNumber, false);showPresetEditDialog();}
                    opacity:     _editingLayer == _layerMission ? 1 : editorMap._nonInteractiveOpacity
                    interactive: _editingLayer == _layerMission
                    vehicle:     _planMasterController.controllerVehicle
                }
            }

            // Add lines between waypoints
            MissionLineView {
                showSpecialVisual:  _missionController.isROIBeginCurrentItem
                model:              _missionController.simpleFlightPathSegments
                opacity:            _editingLayer == _layerMission ? 1 : editorMap._nonInteractiveOpacity
            }

            // Direction arrows in waypoint lines
            MapItemView {
                model: _editingLayer == _layerMission ? _missionController.directionArrows : undefined

                delegate: MapLineArrow {
                    fromCoord:      object ? object.coordinate1 : undefined
                    toCoord:        object ? object.coordinate2 : undefined
                    arrowPosition:  3
                    z:              QGroundControl.zOrderWaypointLines + 1
                }
            }

            // Incomplete segment lines
            MapItemView {
                model: _missionController.incompleteComplexItemLines

                delegate: MapPolyline {
                    path:       [ object.coordinate1, object.coordinate2 ]
                    line.width: 1
                    line.color: "red"
                    z:          QGroundControl.zOrderWaypointLines
                    opacity:    _editingLayer == _layerMission ? 1 : editorMap._nonInteractiveOpacity
                }
            }

            // UI for splitting the current segment
            MapQuickItem {
                id:             splitSegmentItem
                anchorPoint.x:  sourceItem.width / 2
                anchorPoint.y:  sourceItem.height / 2
                z:              QGroundControl.zOrderWaypointLines + 1
                visible:        _editingLayer == _layerMission

                sourceItem: SplitIndicator {
                    onClicked:  _missionController.insertSimpleMissionItem(splitSegmentItem.coordinate,
                                                                           _missionController.currentPlanViewVIIndex,
                                                                           true /* makeCurrentItem */)
                }

                function _updateSplitCoord() {
                    if (_missionController.splitSegment) {
                        var distance = _missionController.splitSegment.coordinate1.distanceTo(_missionController.splitSegment.coordinate2)
                        var azimuth = _missionController.splitSegment.coordinate1.azimuthTo(_missionController.splitSegment.coordinate2)
                        splitSegmentItem.coordinate = _missionController.splitSegment.coordinate1.atDistanceAndAzimuth(distance / 2, azimuth)
                    } else {
                        coordinate = QtPositioning.coordinate()
                    }
                }

                Connections {
                    target:                 _missionController
                    function onSplitSegmentChanged()  { splitSegmentItem._updateSplitCoord() }
                }

                Connections {
                    target:                 _missionController.splitSegment
                    function onCoordinate1Changed()   { splitSegmentItem._updateSplitCoord() }
                    function onCoordinate2Changed()   { splitSegmentItem._updateSplitCoord() }
                }
            }

            // Add the vehicles to the map
            MapItemView {
                model: QGroundControl.multiVehicleManager.vehicles
                delegate: VehicleMapItem {
                    vehicle:        object
                    coordinate:     object.coordinate
                    map:            editorMap
                    size:           ScreenTools.defaultFontPixelHeight * 3
                    z:              QGroundControl.zOrderMapItems - 1
                }
            }

            GeoFenceMapVisuals {
                map:                    editorMap
                myGeoFenceController:   _geoFenceController
                interactive:            _editingLayer == _layerGeoFence
                homePosition:           _missionController.plannedHomePosition
                planView:               true
                opacity:                _editingLayer != _layerGeoFence ? editorMap._nonInteractiveOpacity : 1
            }

            RallyPointMapVisuals {
                map:                    editorMap
                myRallyPointController: _rallyPointController
                interactive:            _editingLayer == _layerRallyPoints
                planView:               true
                opacity:                _editingLayer != _layerRallyPoints ? editorMap._nonInteractiveOpacity : 1
            }

            // Airspace overlap support
            MapItemView {
                model:              _airspaceEnabled && QGroundControl.airspaceManager.airspaceVisible ? QGroundControl.airspaceManager.airspaces.circles : []
                delegate: MapCircle {
                    center:         object.center
                    radius:         object.radius
                    color:          object.color
                    border.color:   object.lineColor
                    border.width:   object.lineWidth
                }
            }

            MapItemView {
                model:              _airspaceEnabled && QGroundControl.airspaceManager.airspaceVisible ? QGroundControl.airspaceManager.airspaces.polygons : []
                delegate: MapPolygon {
                    path:           object.polygon
                    color:          object.color
                    border.color:   object.lineColor
                    border.width:   object.lineWidth
                }
            }
        }

        //-----------------------------------------------------------
        // Left tool strip
        ToolStrip {
            id:                 toolStrip
            anchors.margins:    _toolsMargin
            anchors.left:       parent.left
            anchors.top:        parent.top
            z:                  QGroundControl.zOrderWidgets
            maxHeight:          parent.height - toolStrip.y
            title:              qsTr("Plan")
            visible: !globals.toolSelectMode

            readonly property int flyButtonIndex:       0
            readonly property int presetButtonIndex:    1
            readonly property int fileButtonIndex:      2
            readonly property int takeoffButtonIndex:   3
            readonly property int waypointButtonIndex:  4
            readonly property int roiButtonIndex:       5
            readonly property int patternButtonIndex:   6
            readonly property int landButtonIndex:      7
            readonly property int centerButtonIndex:    8


            property bool _isRallyLayer:    _editingLayer == _layerRallyPoints
            property bool _isMissionLayer:  _editingLayer == _layerMission

            ToolStripActionList {
                id: toolStripActionList
                model: [
                    ToolStripAction {
                        text:           qsTr("Fly")
                        iconSource:     "/qmlimages/PaperPlane.svg"
                        onTriggered:    mainWindow.showFlyView()
                    },
                    ToolStripAction {
                        text:                   qsTr("Preset")
                        enabled:                !_planMasterController.syncInProgress
                        visible:                true
                        showAlternateIcon:      _planMasterController.dirty
                        iconSource:             "/qmlimages/MapSync.svg"
                        alternateIconSource:    "/qmlimages/MapSyncChanged.svg"
                        onTriggered: showPresetSelectDialog()
                        //dropPanelComponent:     presetDropPanel
                    },
                    ToolStripAction {
                        text:                   qsTr("File")
                        enabled:                !_planMasterController.syncInProgress
                        visible:                true
                        showAlternateIcon:      _planMasterController.dirty
                        iconSource:             "/qmlimages/MapSync.svg"
                        alternateIconSource:    "/qmlimages/MapSyncChanged.svg"
                        dropPanelComponent:     syncDropPanel
                    },
                    ToolStripAction {
                        text:       qsTr("Takeoff")
                        iconSource: "/res/takeoff.svg"
                        enabled:    _missionController.isInsertTakeoffValid
                        visible:    toolStrip._isMissionLayer && !_planMasterController.controllerVehicle.rover
                        onTriggered: {
                            toolStrip.allAddClickBoolsOff()
                            insertTakeItemAfterCurrent()
                        }
                    },
                    ToolStripAction {
                        id:                 addWaypointRallyPointAction
                        text:               _editingLayer == _layerRallyPoints ? qsTr("Rally Point") : qsTr("Waypoint")
                        iconSource:         "/qmlimages/MapAddMission.svg"
                        enabled:            toolStrip._isRallyLayer ? true : _missionController.flyThroughCommandsAllowed
                        visible:            toolStrip._isRallyLayer || toolStrip._isMissionLayer
                        checkable:          true
                    },
                    ToolStripAction {
                        text:               _missionController.isROIActive ? qsTr("Cancel ROI") : qsTr("ROI")
                        iconSource:         "/qmlimages/MapAddMission.svg"
                        enabled:            !_missionController.onlyInsertTakeoffValid
                        visible:            toolStrip._isMissionLayer && _planMasterController.controllerVehicle.roiModeSupported
                        checkable:          !_missionController.isROIActive
                        onCheckedChanged:   _addROIOnClick = checked
                        onTriggered: {
                            if (_missionController.isROIActive) {
                                toolStrip.allAddClickBoolsOff()
                                insertCancelROIAfterCurrent()
                            }
                        }
                        property bool myAddROIOnClick: _addROIOnClick
                        onMyAddROIOnClickChanged: checked = _addROIOnClick
                    },
                    ToolStripAction {
                        text:               _singleComplexItem ? _missionController.complexMissionItemNames[0] : qsTr("Pattern")
                        iconSource:         "/qmlimages/MapDrawShape.svg"
                        enabled:            _missionController.flyThroughCommandsAllowed
                        visible:            toolStrip._isMissionLayer
                        dropPanelComponent: _singleComplexItem ? undefined : patternDropPanel
                        onTriggered: {
                            toolStrip.allAddClickBoolsOff()
                            if (_singleComplexItem) {
                                insertComplexItemAfterCurrent(_missionController.complexMissionItemNames[0])
                            }
                        }
                    },
                    ToolStripAction {
                        text:       _planMasterController.controllerVehicle.multiRotor ? qsTr("Return") : qsTr("Land")
                        iconSource: "/res/rtl.svg"
                        enabled:    _missionController.isInsertLandValid
                        visible:    toolStrip._isMissionLayer
                        onTriggered: {
                            toolStrip.allAddClickBoolsOff()
                            insertLandItemAfterCurrent()
                        }
                    },
                    ToolStripAction {
                        text:               qsTr("Center")
                        iconSource:         "/qmlimages/MapCenter.svg"
                        enabled:            true
                        visible:            true
                        dropPanelComponent: centerMapDropPanel
                    }
                ]
            }

            model: toolStripActionList.model

            function allAddClickBoolsOff() {
                _addROIOnClick =        false
                addWaypointRallyPointAction.checked = false
            }

            onDropped: allAddClickBoolsOff()
        }

        //-----------------------------------------------------------
        // Right pane for mission editing controls
        Rectangle {
            id:                 rightPanel
            height:             parent.height
            width:              _rightPanelWidth
            color:              qgcPal.window
            opacity:            layerTabBar.visible ? 0.2 : 0
            anchors.bottom:     parent.bottom
            anchors.right:      parent.right
            anchors.rightMargin: _toolsMargin
            visible: !globals.toolSelectMode
        }
        //-------------------------------------------------------
        // Right Panel Controls
        Item {
            anchors.fill:           rightPanel
            anchors.topMargin:      _toolsMargin
            visible: !globals.toolSelectMode
            DeadMouseArea {
                anchors.fill:   parent
            }
            Column {
                id:                 rightControls
                spacing:            ScreenTools.defaultFontPixelHeight * 0.5
                anchors.left:       parent.left
                anchors.right:      parent.right
                anchors.top:        parent.top
                //-------------------------------------------------------
                // Airmap Airspace Control
                AirspaceControl {
                    id:             airspaceControl
                    width:          parent.width
                    visible:        _airspaceEnabled
                    planView:       true
                    showColapse:    true
                }
                //-------------------------------------------------------
                // Mission Controls (Colapsed)
                Rectangle {
                    width:      parent.width
                    height:     planControlColapsed ? colapsedRow.height + ScreenTools.defaultFontPixelHeight : 0
                    color:      qgcPal.missionItemEditor
                    radius:     _radius
                    visible:    planControlColapsed && _airspaceEnabled
                    Row {
                        id:                     colapsedRow
                        spacing:                ScreenTools.defaultFontPixelWidth
                        anchors.left:           parent.left
                        anchors.leftMargin:     ScreenTools.defaultFontPixelWidth
                        anchors.verticalCenter: parent.verticalCenter
                        QGCColoredImage {
                            width:              height
                            height:             ScreenTools.defaultFontPixelWidth * 2.5
                            sourceSize.height:  height
                            source:             "qrc:/res/waypoint.svg"
                            color:              qgcPal.text
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        QGCLabel {
                            text:               qsTr("Plan")
                            color:              qgcPal.text
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    QGCColoredImage {
                        width:                  height
                        height:                 ScreenTools.defaultFontPixelWidth * 2.5
                        sourceSize.height:      height
                        source:                 QGroundControl.airmapSupported ? "qrc:/airmap/expand.svg" : ""
                        color:                  "white"
                        visible:                QGroundControl.airmapSupported
                        anchors.right:          parent.right
                        anchors.rightMargin:    ScreenTools.defaultFontPixelWidth
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    MouseArea {
                        anchors.fill:   parent
                        enabled:        QGroundControl.airmapSupported
                        onClicked: {
                            QGroundControl.airspaceManager.airspaceVisible = false
                        }
                    }
                }
                //-------------------------------------------------------
                // Mission Controls (Expanded)
                QGCTabBar {
                    id:         layerTabBar
                    width:      parent.width
                    visible:    (!planControlColapsed || !_airspaceEnabled) && QGroundControl.corePlugin.options.enablePlanViewSelector
                    Component.onCompleted: currentIndex = 0
                    QGCTabButton {
                        text:       qsTr("Mission")
                    }
                    QGCTabButton {
                        text:       qsTr("Fence")
                        enabled:    _geoFenceController.supported
                    }
                    QGCTabButton {
                        text:       qsTr("Rally")
                        enabled:    _rallyPointController.supported
                    }
                }
            }
            //-------------------------------------------------------
            // Mission Item Editor
            Item {
                id:                     missionItemEditor
                anchors.left:           parent.left
                anchors.right:          parent.right
                anchors.top:            rightControls.bottom
                anchors.topMargin:      ScreenTools.defaultFontPixelHeight * 0.25
                anchors.bottom:         parent.bottom
                anchors.bottomMargin:   ScreenTools.defaultFontPixelHeight * 0.25
                visible:                _editingLayer == _layerMission && !planControlColapsed
                QGCListView {
                    id:                 missionItemEditorListView
                    anchors.fill:       parent
                    spacing:            ScreenTools.defaultFontPixelHeight / 4
                    orientation:        ListView.Vertical
                    model:              _missionController.visualItems
                    cacheBuffer:        Math.max(height * 2, 0)
                    clip:               true
                    currentIndex:       _missionController.currentPlanViewSeqNum
                    highlightMoveDuration: 250
                    visible:            _editingLayer == _layerMission && !planControlColapsed
                    //-- List Elements
                    delegate: MissionItemEditor {
                        map:            editorMap
                        masterController:  _planMasterController
                        missionItem:    object
                        width:          parent?parent.width:0
                        readOnly:       false
                        onClicked:      _missionController.setCurrentPlanViewSeqNum(object.sequenceNumber, false)
                        onRemove: {
                            var removeVIIndex = index
                            _missionController.removeVisualItem(removeVIIndex)
                            if (removeVIIndex >= _missionController.visualItems.count) {
                                removeVIIndex--
                            }
                        }
                        onSelectNextNotReadyItem:   selectNextNotReady()
                    }
                }
            }
            // GeoFence Editor
            GeoFenceEditor {
                anchors.top:            rightControls.bottom
                anchors.topMargin:      ScreenTools.defaultFontPixelHeight * 0.25
                anchors.bottom:         parent.bottom
                anchors.left:           parent.left
                anchors.right:          parent.right
                myGeoFenceController:   _geoFenceController
                flightMap:              editorMap
                visible:                _editingLayer == _layerGeoFence
            }

            // Rally Point Editor
            RallyPointEditorHeader {
                id:                     rallyPointHeader
                anchors.top:            rightControls.bottom
                anchors.topMargin:      ScreenTools.defaultFontPixelHeight * 0.25
                anchors.left:           parent.left
                anchors.right:          parent.right
                visible:                _editingLayer == _layerRallyPoints
                controller:             _rallyPointController
            }
            RallyPointItemEditor {
                id:                     rallyPointEditor
                anchors.top:            rallyPointHeader.bottom
                anchors.topMargin:      ScreenTools.defaultFontPixelHeight * 0.25
                anchors.left:           parent.left
                anchors.right:          parent.right
                visible:                _editingLayer == _layerRallyPoints && _rallyPointController.points.count
                rallyPoint:             _rallyPointController.currentRallyPoint
                controller:             _rallyPointController
            }
        }

        TerrainStatus {
            id:                 terrainStatus
            anchors.margins:    _toolsMargin
            anchors.leftMargin: 0
            anchors.left:       mapScale.left
            anchors.right:      rightPanel.left
            anchors.bottom:     parent.bottom
            height:             ScreenTools.defaultFontPixelHeight * 7
            missionController:  _missionController
            visible:            _internalVisible && _editingLayer === _layerMission && QGroundControl.corePlugin.options.showMissionStatus && !globals.toolSelectMode

            onSetCurrentSeqNum: _missionController.setCurrentPlanViewSeqNum(seqNum, true)

            property bool _internalVisible: _planViewSettings.showMissionItemStatus.rawValue

            function toggleVisible() {
                _internalVisible = !_internalVisible
                _planViewSettings.showMissionItemStatus.rawValue = _internalVisible
            }
        }

        MapScale {
            id:                     mapScale
            anchors.margins:        _toolsMargin
            anchors.bottom:         terrainStatus.visible ? terrainStatus.top : parent.bottom
            anchors.left:           toolStrip.y + toolStrip.height + _toolsMargin > mapScale.y ? toolStrip.right: parent.left
            mapControl:             editorMap
            buttonsOnLeft:          true
            terrainButtonVisible:   _editingLayer === _layerMission
            terrainButtonChecked:   terrainStatus.visible
            onTerrainButtonClicked: terrainStatus.toggleVisible()
            visible: !globals.toolSelectMode
        }
    }

    Component {
        id: syncLoadFromVehicleOverwrite
        QGCViewMessage {
            id:         syncLoadFromVehicleCheck
            message:   qsTr("You have unsaved/unsent changes. Loading from the Vehicle will lose these changes. Are you sure you want to load from the Vehicle?")
            function accept() {
                hideDialog()
                _planMasterController.loadFromVehicle()
            }
        }
    }

    Component {
        id: syncLoadFromFileOverwrite
        QGCViewMessage {
            id:         syncLoadFromVehicleCheck
            message:   qsTr("You have unsaved/unsent changes. Loading from a file will lose these changes. Are you sure you want to load from a file?")
            function accept() {
                hideDialog()
                _planMasterController.loadFromSelectedFile()
            }
        }
    }

    property var createPlanRemoveAllPromptDialogMapCenter
    property var createPlanRemoveAllPromptDialogPlanCreator
    Component {
        id: createPlanRemoveAllPromptDialog
        QGCViewMessage {
            message: qsTr("Are you sure you want to remove current plan and create a new plan? ")
            function accept() {
                createPlanRemoveAllPromptDialogPlanCreator.createPlan(createPlanRemoveAllPromptDialogMapCenter)
                hideDialog()
//                toolSelectDialog.hideDialog()
                showPresetEditDialog()
            }
            function reject() {
                hideDialog()
                showToolSelectDialog()
            }
        }
    }

    Component {
        id: clearVehicleMissionDialog
        QGCViewMessage {
            message: qsTr("Are you sure you want to remove all mission items and clear the mission from the vehicle?")
            function accept() {
                _planMasterController.removeAllFromVehicle()
                _missionController.setCurrentPlanViewSeqNum(0, true)
                hideDialog()
            }
        }
    }

    //- ToolStrip DropPanel Components

    Component {
        id: centerMapDropPanel

        CenterMapDropPanel {
            map:            editorMap
            fitFunctions:   mapFitFunctions
        }
    }

    Component {
        id: patternDropPanel

        ColumnLayout {
            spacing:    ScreenTools.defaultFontPixelWidth * 0.5

            QGCLabel { text: qsTr("Create complex pattern:") }

            Repeater {
                model: _missionController.complexMissionItemNames

                QGCButton {
                    text:               modelData
                    Layout.fillWidth:   true

                    onClicked: {
                        insertComplexItemAfterCurrent(modelData)
                        dropPanel.hide()
                    }
                }
            }
        } // Column
    }

    Component {
        id: syncDropPanel

        ColumnLayout {
            id:         columnHolder
            spacing:    _margin

            property string _overwriteText: (_editingLayer == _layerMission) ? qsTr("Mission overwrite") : ((_editingLayer == _layerGeoFence) ? qsTr("GeoFence overwrite") : qsTr("Rally Points overwrite"))

            QGCLabel {
                id:                 unsavedChangedLabel
                Layout.fillWidth:   true
                wrapMode:           Text.WordWrap
                text:               globals.activeVehicle ?
                                        qsTr("You have unsaved changes. You should upload to your vehicle, or save to a file.") :
                                        qsTr("You have unsaved changes.")
                visible:            _planMasterController.dirty
            }

            SectionHeader {
                id:                 createSection
                Layout.fillWidth:   true
                text:               qsTr("Create Plan")
                showSpacer:         false
            }

            GridLayout {
                columns:            2
                columnSpacing:      _margin
                rowSpacing:         _margin
                Layout.fillWidth:   true
                visible:            createSection.visible

                Repeater {
                    model: _planMasterController.planCreators

                    Rectangle {
                        id:     button
                        width:  ScreenTools.defaultFontPixelHeight * 7
                        height: planCreatorNameLabel.y + planCreatorNameLabel.height
                        color:  button.pressed || button.highlighted ? qgcPal.buttonHighlight : qgcPal.button

                        property bool highlighted: mouseArea.containsMouse
                        property bool pressed:     mouseArea.pressed

                        Image {
                            id:                 planCreatorImage
                            anchors.left:       parent.left
                            anchors.right:      parent.right
                            source:             object.imageResource
                            sourceSize.width:   width
                            fillMode:           Image.PreserveAspectFit
                            mipmap:             true
                        }

                        QGCLabel {
                            id:                     planCreatorNameLabel
                            anchors.top:            planCreatorImage.bottom
                            anchors.left:           parent.left
                            anchors.right:          parent.right
                            horizontalAlignment:    Text.AlignHCenter
                            text:                   object.name
                            color:                  button.pressed || button.highlighted ? qgcPal.buttonHighlightText : qgcPal.buttonText
                        }

                        QGCMouseArea {
                            id:                 mouseArea
                            anchors.fill:       parent
                            hoverEnabled:       true
                            preventStealing:    true
                            onClicked:          {
                                if (_planMasterController.containsItems) {
                                    createPlanRemoveAllPromptDialogMapCenter = _mapCenter()
                                    createPlanRemoveAllPromptDialogPlanCreator = object
                                    mainWindow.showComponentDialog(createPlanRemoveAllPromptDialog, qsTr("Create Plan"), mainWindow.showDialogDefaultWidth, StandardButton.Yes | StandardButton.No)
                                } else {
                                    object.createPlan(_mapCenter())
                                }
                                dropPanel.hide()
                            }

                            function _mapCenter() {
                                var centerPoint = Qt.point(editorMap.centerViewport.left + (editorMap.centerViewport.width / 2), editorMap.centerViewport.top + (editorMap.centerViewport.height / 2))
                                return editorMap.toCoordinate(centerPoint, false /* clipToViewPort */)
                            }
                        }
                    }
                }
            }

            SectionHeader {
                id:                 storageSection
                Layout.fillWidth:   true
                text:               qsTr("Storage")
            }

            GridLayout {
                columns:            3
                rowSpacing:         _margin
                columnSpacing:      ScreenTools.defaultFontPixelWidth
                visible:            storageSection.visible

                /*QGCButton {
                    text:               qsTr("New...")
                    Layout.fillWidth:   true
                    onClicked:  {
                        dropPanel.hide()
                        if (_planMasterController.containsItems) {
                            mainWindow.showComponentDialog(removeAllPromptDialog, qsTr("New Plan"), mainWindow.showDialogDefaultWidth, StandardButton.Yes | StandardButton.No)
                        }
                    }
                }*/

                QGCButton {
                    text:               qsTr("Open...")
                    Layout.fillWidth:   true
                    enabled:            !_planMasterController.syncInProgress
                    onClicked: {
                        dropPanel.hide()
                        if (_planMasterController.dirty) {
                            mainWindow.showComponentDialog(syncLoadFromFileOverwrite, columnHolder._overwriteText, mainWindow.showDialogDefaultWidth, StandardButton.Yes | StandardButton.Cancel)
                        } else {
                            _planMasterController.loadFromSelectedFile()
                        }
                    }
                }

                QGCButton {
                    text:               qsTr("Save")
                    Layout.fillWidth:   true
                    enabled:            !_planMasterController.syncInProgress && _planMasterController.currentPlanFile !== ""
                    onClicked: {
                        dropPanel.hide()
                        if(_planMasterController.currentPlanFile !== "") {
                            _planMasterController.saveToCurrent()
                        } else {
                            _planMasterController.saveToSelectedFile()
                        }
                    }
                }

                QGCButton {
                    text:               qsTr("Save As...")
                    Layout.fillWidth:   true
                    enabled:            !_planMasterController.syncInProgress && _planMasterController.containsItems
                    onClicked: {
                        dropPanel.hide()
                        _planMasterController.saveToSelectedFile()
                    }
                }

                QGCButton {
                    Layout.columnSpan:  3
                    Layout.fillWidth:   true
                    text:               qsTr("Save Mission Waypoints As KML...")
                    enabled:            !_planMasterController.syncInProgress && _visualItems.count > 1
                    onClicked: {
                        // First point does not count
                        if (_visualItems.count < 2) {
                            mainWindow.showComponentDialog(noItemForKML, qsTr("KML"), mainWindow.showDialogDefaultWidth, StandardButton.Cancel)
                            return
                        }
                        dropPanel.hide()
                        _planMasterController.saveKmlToSelectedFile()
                    }
                }
            }

            SectionHeader {
                id:                 vehicleSection
                Layout.fillWidth:   true
                text:               qsTr("Vehicle")
            }

            RowLayout {
                Layout.fillWidth:   true
                spacing:            _margin
                visible:            vehicleSection.visible

                QGCButton {
                    text:               qsTr("Upload")
                    Layout.fillWidth:   true
                    enabled:            !_planMasterController.offline && !_planMasterController.syncInProgress && _planMasterController.containsItems
                    visible:            !QGroundControl.corePlugin.options.disableVehicleConnection
                    onClicked: {
                        dropPanel.hide()
                        _planMasterController.upload()
                    }
                }

                QGCButton {
                    text:               qsTr("Download")
                    Layout.fillWidth:   true
                    enabled:            !_planMasterController.offline && !_planMasterController.syncInProgress
                    visible:            !QGroundControl.corePlugin.options.disableVehicleConnection
                    onClicked: {
                        dropPanel.hide()
                        if (_planMasterController.dirty) {
                            mainWindow.showComponentDialog(syncLoadFromVehicleOverwrite, columnHolder._overwriteText, mainWindow.showDialogDefaultWidth, StandardButton.Yes | StandardButton.Cancel)
                        } else {
                            _planMasterController.loadFromVehicle()
                        }
                    }
                }

                QGCButton {
                    text:               qsTr("Clear")
                    Layout.fillWidth:   true
                    Layout.columnSpan:  2
                    enabled:            !_planMasterController.offline && !_planMasterController.syncInProgress
                    visible:            !QGroundControl.corePlugin.options.disableVehicleConnection
                    onClicked: {
                        dropPanel.hide()
                        mainWindow.showComponentDialog(clearVehicleMissionDialog, text, mainWindow.showDialogDefaultWidth, StandardButton.Yes | StandardButton.Cancel)
                    }
                }
            }
        }
    }
    // Progress bar
    Connections {
        target: _missionController
        function onProgressPctChanged(progressPct) {
            console.debug("mission upload progress:",progressPct)
            console.debug("offline",_planMasterController.offline,"\n syncInProgress:",_planMasterController.syncInProgress,"\n contains Item:",_planMasterController.containsItems)
            if (progressPct === 1 && _planMasterController.containsItems) {
                switchToMonitorTimer.start()
//                missionStats.visible = false
//                uploadCompleteText.visible = true
//                progressBar.visible = false
//                resetProgressTimer.start()
            } else if (progressPct > 0) {
//                progressBar.visible = true
            }
        }
    }
    function showPresetSelectDialog(){
        presetPopup.open()
        pageIndicator.currentIndex = 0
//        toolSelectDialog.hideDialog()
//        showPopupDialogFromComponent(presetSelectDialogComponent)
        preventViewSwitch()
    }

//    Component {
//        id: presetSelectDialogComponent
//        QGCPopupDialog {
//            id:         presetSelectDialog
//            title:      qsTr("Select Preset")
//            buttons:    /*StandardButton.NoButton*/StandardButton.Close
//            titleBarEnabled: true

//            ColumnLayout {
//                id:         columnHolder
//                width: innerLayout.width
//                height: innerLayout.height + _margin

//                property string _overwriteText: (_editingLayer == _layerMission) ? qsTr("Mission overwrite") : ((_editingLayer == _layerGeoFence) ? qsTr("GeoFence overwrite") : qsTr("Rally Points overwrite"))
////                Rectangle {
////                    Layout.alignment: Qt.AlignLeft
////                    Layout.preferredHeight:45
////                    Layout.preferredWidth:80
////                    Button {
////                        anchors.fill: parent
////                        text: "back"
////                        onClicked: {
////                            hideDialog()
////                            showToolSelectDialog()
////                            //                                mapFitFunctions.fitMapViewportToMissionItems()
////                            //                                loaded = false
////                            //                                _planMasterController.upload()
////                        }
////                    }
////                }

//                GridLayout {
//                    id: innerLayout
//                    columns:            2
//                    Layout.topMargin: ScreenTools.defaultFontPixelWidth
//                    Layout.alignment: Qt.AlignCenter
//                    visible:            true//createSection.visible

//                    Repeater {
//                        model: _planMasterController.planCreatorsPreset

//                        Rectangle {
//                            id:     button
//                            Layout.rowSpan: 1
//                            Layout.columnSpan: 1

//                            width:  ScreenTools.defaultFontPixelHeight * 15
//                            height: planCreatorNameLabel.y + planCreatorNameLabel.height
//                            color:  button.pressed || button.highlighted ? qgcPal.buttonHighlight : qgcPal.windowShade

//                            property bool highlighted: mouseArea.containsMouse
//                            property bool pressed:     mouseArea.pressed

//                            Image {
//                                id:                 planCreatorImage
//                                anchors.left:       parent.left
//                                anchors.right:      parent.right
//                                source:             object.imageResource
//                                sourceSize.width:   width
//                                fillMode:           Image.PreserveAspectFit
//                                mipmap:             true
//                            }

//                            QGCLabel {
//                                id:                     planCreatorNameLabel
//                                anchors.top:            planCreatorImage.bottom
//                                anchors.left:           parent.left
//                                anchors.right:          parent.right
//                                height:                 ScreenTools.defaultFontPixelHeight*2
//                                horizontalAlignment:    Text.AlignHCenter
//                                verticalAlignment:      Text.AlignVCenter
//                                font.pixelSize:         height*0.5
//                                text:                   ""//object.name
//                                color:                  button.pressed || button.highlighted ? qgcPal.buttonHighlightText : qgcPal.buttonText
//                            }

//                            QGCMouseArea {
//                                id:                 mouseArea
//                                anchors.fill:       parent
//                                hoverEnabled:       true
//                                preventStealing:    true
//                                onClicked:{
//                                    presetSelectDialog.hideDialog()
//                                    globals.toolSelectMode = true
//                                    if (_planMasterController.containsItems) {
//                                        createPlanRemoveAllPromptDialogMapCenter = _mapCenter()
//                                        createPlanRemoveAllPromptDialogPlanCreator = object
//                                        mainWindow.showComponentDialog(createPlanRemoveAllPromptDialog, qsTr("Create Plan"), mainWindow.showDialogDefaultWidth, StandardButton.Yes | StandardButton.No)
//                                    } else {
//                                        object.createPlan(_mapCenter())
//                                        showPresetEditDialog(object.presetType)
//                                    }
//                                }

//                                function _mapCenter() {
//                                    var centerPoint = Qt.point(editorMap.centerViewport.left + (editorMap.centerViewport.width / 2), editorMap.centerViewport.top + (editorMap.centerViewport.height / 2))
//                                    return editorMap.toCoordinate(centerPoint, false /* clipToViewPort */)
//                                }
//                            }
//                        }
//                    }
//                }
//            }
//        }
//    }
    function showPresetEditDialog(type){

        switch(type){
            case PlanView.PresetType.TypeNone:{
                break;
            }
            case PlanView.PresetType.TypeAB:{
                console.log("typeAB")
                session.model = presetModels[1]
                break;
            }
            case PlanView.PresetType.TypeABA:{
                break;
            }
            case PlanView.PresetType.TypeABC:{
                break;
            }
            case PlanView.PresetType.TypeAZ:{
                break;
            }
        }
        presetPopup.open()
        pageIndicator.currentIndex = 1
//        showPopupDialogFromComponent(presetEditDialogComponent)
    }
    function showAltitudeProfile(show){
        altitudeProfile.visible = show
        _altitudeProfiletimer.start()
    }

    Component {
        id: presetDelegate
        Rectangle {
            id:_rootListDelegate
            width: parent.width
            height: childrenRect.height
            color: "white"
            border.color: "gray"
            RowLayout {
                Text {
                    Layout.margins: 5
                    text: modelData.text
                    horizontalAlignment: TextField.AlignLeft
                    verticalAlignment: TextField.AlignVCenter
                }
                Text {
                    Layout.margins: 5
                    text: "("+modelData.coordinate.latitude+","+modelData.coordinate.longitude+")"
                    horizontalAlignment: TextField.AlignRight
                    verticalAlignment: TextField.AlignVCenter
                }
            }
            MouseArea {
                hoverEnabled: true
                anchors.fill: parent
                onEntered: {
                    _rootListDelegate.color = "lightblue"
                }
                onExited: {
                    _rootListDelegate.color = "white"
                }
                onClicked: {
                    _rootListDelegate.ListView.view.currentIndex = index
                    _rootListDelegate.ListView.view.presetIndexChanged(index);
                    console.log("selected index",_rootListDelegate.ListView.view)
                }
            }
        }
    }
    /********************************************************************************/

    Popup {
        id:presetPopup
        width: 750
        height: 600
        padding: 5
        modal: true
        closePolicy: Popup.NoAutoClose
        anchors.centerIn: parent
        clip:true
        background: Rectangle {
            color:qgcPal.windowShadeDark
        }
        onOpened: {
            if(presetEditPage.loaded && session.model[0].preset){

                titleA.location = QtPositioning.coordinate(session.model[0].preset.coordinate.latitude,session.model[0].preset.coordinate.longitude)
                titleB.location = QtPositioning.coordinate(session.model[1].preset.coordinate.latitude,session.model[1].preset.coordinate.longitude)
                titleA.altitude = session.model[0].preset.coordinate.altitude.toFixed(2)
                titleB.altitude = session.model[1].preset.coordinate.altitude.toFixed(2)
            }


        }

        ColumnLayout {
            id: column
            anchors.fill: parent
            RowLayout {
                id: row
                Layout.fillWidth: true
                implicitHeight: ScreenTools.defaultFontPixelHeight*3
                Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                Button {
                    id: _button1
                    text: qsTr("Back")
                    contentItem: Text {
                        text: _button1.text
                        font: _button1.font
                        color: qgcPal.buttonText
                    }
//                    style: e {
//                        text: qsTr("Back")
//                        color: qgcPal.buttonText
//                    }
                    visible: true
                    Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                    onClicked: {
                        if(pageIndicator.currentIndex == 0){
                            presetPopup.close()
                            showToolSelectDialog()
                        } else if(pageIndicator.currentIndex > 0){
                            pageIndicator.currentIndex--;
                        }
                    }
                    background: Rectangle {
                        color: qgcPal.windowShade
                    }
                }
                Item {
                    id: spacer0
                    Layout.fillWidth: true
                }

                PageIndicator {
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                    id: pageIndicator
                    interactive: true
                    count: view.count
                    currentIndex: view.currentIndex
                }
                Item {
                    id: spacer1
                    Layout.fillWidth: true
                }

//                Button {
//                    id: _button
//                    Layout.alignment: Qt.AlignRight | Qt.AlignTop
//                    visible: true
//                    text: qsTr("Next")
//                    autoExclusive: true
//                    checkable: true
//                }
            }
            SwipeView {
                id:view
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                currentIndex: pageIndicator.currentIndex
                clip:true
                Item {
                    id: presetSelectPage
                    GridLayout {
                        id: innerLayout
                        anchors.fill: parent
                        rows: 2
                        columns: 2
                        Repeater {
                            model: _planMasterController.planCreatorsPreset
                            Rectangle {
                                id:button
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color:  button.pressed || button.highlighted ? qgcPal.buttonHighlight : qgcPal.windowShade

                                property bool highlighted: mouseArea.containsMouse
                                property bool pressed:     mouseArea.pressed
                                ColumnLayout {
                                    id: buttonLayout
                                    anchors.fill: parent
                                    spacing: 5
                                    Image {
//                                        id:                 planCreatorImage
                                        source:             object.imageResource
//                                        Layout.minimumHeight: 50
//                                        Layout.minimumWidth: 50
//                                        Layout.maximumHeight: 100
//                                        Layout.maximumWidth: 100
                                        Layout.fillHeight: true
                                        Layout.fillWidth: true
                                        fillMode: Image.PreserveAspectFit
                                    }
                                    Text {
//                                        id:                     planCreatorNameLabel
                                        horizontalAlignment:    Text.AlignHCenter
                                        verticalAlignment:      Text.AlignVCenter
                                        font.pixelSize:         ScreenTools.defaultFontPixelHeight
                                        text:                   ""//object.name
                                        color:                  button.pressed || button.highlighted ? qgcPal.buttonHighlightText : qgcPal.buttonText
                                    }
                                }
                                MouseArea {
                                    id:                 mouseArea
                                    anchors.fill:       parent
                                    hoverEnabled:       true
//                                    preventStealing:    true
                                    onClicked:{
                                        console.log("size:",button.width,button.height)
//                                        presetSelectDialog.hideDialog()
                                        globals.toolSelectMode = true
                                        if (_planMasterController.containsItems) {
                                            createPlanRemoveAllPromptDialogMapCenter = _mapCenter()
                                            createPlanRemoveAllPromptDialogPlanCreator = object
                                            mainWindow.showComponentDialog(createPlanRemoveAllPromptDialog, qsTr("Create Plan"), mainWindow.showDialogDefaultWidth, StandardButton.Yes | StandardButton.No)
                                        } else {
                                            object.createPlan(_mapCenter())
                                            showPresetEditDialog(object.presetType)
                                        }
                                    }

                                    function _mapCenter() {
                                        var centerPoint = Qt.point(editorMap.centerViewport.left + (editorMap.centerViewport.width / 2), editorMap.centerViewport.top + (editorMap.centerViewport.height / 2))
                                        return editorMap.toCoordinate(centerPoint, false /* clipToViewPort */)
                                    }
                                }
                            }
                        }
                    }
                }


                Item {
                    id:presetEditPage
                    property bool checked: false
                    property bool loaded: false
                    Component.onCompleted: {
                        loaded = true
                        console.log("onCompleted:activeVehicle",globals.activeVehicle?globals.activeVehicle.coordinate:"")
                    }
                    ColumnLayout {
                        anchors.fill: parent
                        GridLayout {
                            Layout.fillWidth: true
                            columnSpacing: 10
                            Layout.margins: 8
                            columns: 2
                            Rectangle {
                                antialiasing: true
                                Layout.preferredHeight: 120
                                Layout.fillWidth: true
                                color: "#00ffffff"
                                MouseArea {
                                    propagateComposedEvents: true
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        presetEditPage.checked = false
                                    }
                                    TitleBoxContainer {
                                        id:titleA
                                        ma:parent
                                        anchors.fill:parent
                                        title:"Start"
                                        titleColor:!presetEditPage.checked?qgcPal.buttonHighlight:"gray"
                                        textColor:"white"
                                        textEditColor:"white"
                                        titleTextColor:!presetEditPage.checked?qgcPal.windowShade:"white"
                                        foregroundColor:qgcPal.windowShade
                                        unit:"m"
                                        index:session.model[0].index
                                        location:session.model[0].preset===null?QtPositioning.coordinate():QtPositioning.coordinate(session.model[0].preset.coordinate.latitude,session.model[0].preset.coordinate.longitude)
                                        altitude:session.model[0].preset===null?0:session.model[0].preset.coordinate.altitude
                                        name:session.model[0].preset===null?"":session.model[0].preset.text
                                        onLocationChanged: {
                                            if(!session.model[0].preset){return;}
                                            _visualItems.get(index).coordinate = location
                                            session.model[0].preset.coordinate.latitude = location.latitude
                                            session.model[0].preset.coordinate.longitude = location.longitude
                                        }
                                        onAltitudeChanged: {
                                            if(!session.model[0].preset){return;}
                                            _visualItems.get(index).altitude.value = altitude
                                            session.model[0].preset.coordinate.altitude = altitude
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                antialiasing: true
                                Layout.preferredHeight:120
                                Layout.fillWidth: true
                                color: "#00ffffff"
                                MouseArea {
                                    propagateComposedEvents: true
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        presetEditPage.checked = true
                                    }
                                    TitleBoxContainer {
                                        id:titleB
                                        ma:parent
                                        anchors.fill:parent
                                        title:"Destination"
                                        titleColor:presetEditPage.checked?qgcPal.buttonHighlight:"gray"
                                        textColor:"white"
                                        textEditColor:"white"
                                        titleTextColor:presetEditPage.checked?qgcPal.windowShade:"white"
                                        foregroundColor:qgcPal.windowShade
                                        unit:"m"
                                        index:session.model[1].index
                                        location:session.model===null?QtPositioning.coordinate():QtPositioning.coordinate(session.model[1].preset.coordinate.latitude,session.model[1].preset.coordinate.longitude)
                                        altitude:session.model===null?0:session.model[1].preset.coordinate.altitude
                                        name:session.model[1].preset===null?"":session.model[1].preset.text
                                        onLocationChanged: {
                                            if(!session.model[1].preset){return;}
                                            _visualItems.get(index).coordinate = location
                                            session.model[1].preset.coordinate.latitude = location.latitude
                                            session.model[1].preset.coordinate.longitude = location.longitude
                                        }
                                        onAltitudeChanged: {
                                            if(!session.model[1].preset){return;}
                                            _visualItems.get(index).altitude.value = altitude
                                            session.model[1].preset.coordinate.altitude = altitude
                                        }
                                        Component.onCompleted: {
                                            let x = {};
                                            x.index = this.index
                                            x.id = this
                                            presetContainers.push(x)
                                        }
                                    }
                                }
                            }
                        }
                        RowLayout {
                            Layout.margins: 8
                            Flickable {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                ListView {
                                    model:presetModelDefault
                                    anchors.fill: parent
                                    delegate: presetDelegate
                                    signal presetIndexChanged(int presetIndex);

                                    onPresetIndexChanged: {
        //                                if(presetModelSession.active)
                                        if(!presetEditPage.loaded){presetIndex = -1;return;}
                                        if(session.model===null){return;}
                                        if(presetEditPage.checked){
                                            session.model[1].preset = model[presetIndex]
                                            titleB.name = session.model[1].preset.text
                                            titleB.location = QtPositioning.coordinate(session.model[1].preset.coordinate.latitude,session.model[1].preset.coordinate.longitude)
                                            titleB.altitude = session.model[1].preset.coordinate.altitude
        //                                    _visualItems.get(2).coordinate = model[currentIndex].coordinate
        //                                    _visualItems.get(2).altitude.value = model[currentIndex].coordinate.altitude
                                        } else {
                                            session.model[0].preset = model[presetIndex]
                                            titleA.name = session.model[0].preset.text
                                            titleA.location = QtPositioning.coordinate(session.model[0].preset.coordinate.latitude,session.model[0].preset.coordinate.longitude)
                                            titleA.altitude = session.model[0].preset.coordinate.altitude
        //                                   _visualItems.get(1).coordinate = model[currentIndex].coordinate
                                            _visualItems.get(0).coordinate.altitude = globals.activeVehicle?globals.activeVehicle.altitudeAMSL:0
        //                                   _visualItems.get(1).altitude.value = model[currentIndex].coordinate.altitude
                                        }
                                    }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignBottom
                            Layout.margins: 8
                            Item{
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignRight | Qt.AlignBottom
                                Layout.preferredHeight:45
                                Layout.preferredWidth:80
                                Button {
                                    anchors.fill: parent
                                    text: "confirm"
                                    onClicked: {
                                        presetPopup.close()
//                                        hideDialog()
                                        showAltitudeProfile(true)
                                        mapFitFunctions.fitMapViewportToMissionItems()
//                                        presetEditPage.loaded = false
                                        altitudeProfile.update()
        //                                _planMasterController.upload()
                                    }
                                }
                            }
                        }
                    }

//                    Grid {
//                        id: grid
//                        width: 400
//                        height: 400
//                    }
                }
            }
        }
    }

    /*##^##
    Designer {
        D{i:0;formeditorZoom:1.1}D{i:3}D{i:4}D{i:2}D{i:8}D{i:7}D{i:6}D{i:19}D{i:18}D{i:5}
    D{i:1}
    }
    ##^##*/

    /********************************************************************************/
//    Component {
//        id: presetEditDialogComponent
//        QGCPopupDialog {
//            id:         presetEditDialog
//            title:      qsTr("")//qsTr("Select Preset")
//            buttons:    StandardButton.NoButton//StandardButton.Close
//            titleBarEnabled: false
//            height: 480//mainWindow.width
//            width: 640//mainWindow.width
//            property bool checked: false
//            property bool loaded: false
//            Component.onCompleted: {
//                loaded = true
//                console.log("onCompleted:activeVehicle",globals.activeVehicle?globals.activeVehicle.coordinate:"")
//            }

//            //0:Not Set, 1:A->B, 2:A->B->A, 3:A->B->C, 4:A->...->Z
////            property int presetType: 0
//            ColumnLayout {
//                anchors.fill: parent
//                GridLayout {
//                    Layout.fillWidth: true
//                    columnSpacing: 10
//                    Layout.margins: 8
//                    columns: 2

//                    Rectangle {
//                        antialiasing: true
//                        Layout.preferredHeight:120
////                        Layout.preferredWidth:50
//                        Layout.fillWidth: true
//                        color: "#00ffffff"
//                        MouseArea {
//                            propagateComposedEvents: true
//                            anchors.fill: parent
//                            hoverEnabled: true
//                            onClicked: {
//                                checked = false
//                            }
//                            TitleBoxContainer {
//                                id:titleA
//                                ma:parent
//                                anchors.fill:parent
//                                title:"Start"
//                                titleColor:!checked?qgcPal.buttonHighlight:"gray"
//                                textColor:"white"
//                                textEditColor:"white"
//                                titleTextColor:!checked?qgcPal.windowShade:"white"
//                                foregroundColor:qgcPal.windowShade
//                                unit:"m"
//                                index:session.model[0].index
//                                location:session.model[0].preset===null?QtPositioning.coordinate():QtPositioning.coordinate(session.model[0].preset.coordinate.latitude,session.model[0].preset.coordinate.longitude)
//                                altitude:session.model[0].preset===null?0:session.model[0].preset.coordinate.altitude
//                                name:session.model[0].preset===null?"":session.model[0].preset.text
//                                onLocationChanged: {
//                                    if(!session.model[0].preset){return;}
//                                    _visualItems.get(index).coordinate = location
//                                    session.model[0].preset.coordinate.latitude = location.latitude
//                                    session.model[0].preset.coordinate.longitude = location.longitude
//                                }
//                                onAltitudeChanged: {
//                                    if(!session.model[0].preset){return;}
//                                    _visualItems.get(index).altitude.value = altitude
//                                    session.model[0].preset.coordinate.altitude = altitude
//                                }
//                            }
//                        }
//                    }
//                    Rectangle {
//                        antialiasing: true
//                        Layout.preferredHeight:120
//        //                Layout.preferredWidth:50
//                        Layout.fillWidth: true
//                        color: "#00ffffff"
//                        MouseArea {
//                            propagateComposedEvents: true
//                            anchors.fill: parent
//                            hoverEnabled: true
//                            onClicked: {
//                                checked = true
//                            }
//                            TitleBoxContainer {
//                                id:titleB
//                                ma:parent
//                                anchors.fill:parent
//                                title:"Destination"
//                                titleColor:checked?qgcPal.buttonHighlight:"gray"
//                                textColor:"white"
//                                textEditColor:"white"
//                                titleTextColor:checked?qgcPal.windowShade:"white"
//                                foregroundColor:qgcPal.windowShade
//                                unit:"m"
//                                index:session.model[1].index
//                                location:session.model===null?QtPositioning.coordinate():QtPositioning.coordinate(session.model[1].preset.coordinate.latitude,session.model[1].preset.coordinate.longitude)
//                                altitude:session.model===null?0:session.model[1].preset.coordinate.altitude
//                                name:session.model[1].preset===null?"":session.model[1].preset.text
//                                onLocationChanged: {
//                                    if(!session.model[1].preset){return;}
//                                    _visualItems.get(index).coordinate = location
//                                    session.model[1].preset.coordinate.latitude = location.latitude
//                                    session.model[1].preset.coordinate.longitude = location.longitude
//                                }
//                                onAltitudeChanged: {
//                                    if(!session.model[1].preset){return;}
//                                    _visualItems.get(index).altitude.value = altitude
//                                    session.model[1].preset.coordinate.altitude = altitude
//                                }
//                            }
//                        }
//                    }
//                }
//                RowLayout {
//                    Layout.margins: 8
//                    Flickable {
//                        Layout.fillWidth: true
//                        Layout.fillHeight: true
//                        ListView {
//                            model:presetModelDefault
//                            anchors.fill: parent
//                            delegate: presetDelegate
//                            signal presetIndexChanged(int presetIndex);

//                            onPresetIndexChanged: {
////                                if(presetModelSession.active)
//                                if(!loaded){presetIndex = -1;return;}
//                                if(session.model===null){return;}
//                                if(checked){
//                                    session.model[1].preset = model[presetIndex]
//                                    titleB.name = session.model[1].preset.text
//                                    titleB.location = QtPositioning.coordinate(session.model[1].preset.coordinate.latitude,session.model[1].preset.coordinate.longitude)
//                                    titleB.altitude = session.model[1].preset.coordinate.altitude
////                                    _visualItems.get(2).coordinate = model[currentIndex].coordinate
////                                    _visualItems.get(2).altitude.value = model[currentIndex].coordinate.altitude
//                                } else {
//                                    session.model[0].preset = model[presetIndex]
//                                    titleA.name = session.model[0].preset.text
//                                    titleA.location = QtPositioning.coordinate(session.model[0].preset.coordinate.latitude,session.model[0].preset.coordinate.longitude)
//                                    titleA.altitude = session.model[0].preset.coordinate.altitude
////                                   _visualItems.get(1).coordinate = model[currentIndex].coordinate
//                                    _visualItems.get(0).coordinate.altitude = globals.activeVehicle?globals.activeVehicle.altitudeAMSL:0
////                                   _visualItems.get(1).altitude.value = model[currentIndex].coordinate.altitude
//                                }
//                            }
//                        }
//                    }
//                }
//                RowLayout {
//                    Layout.fillWidth: true
//                    Layout.alignment: Qt.AlignBottom
//                    Layout.margins: 8
//                    Rectangle {
//                        Layout.alignment: Qt.AlignLeft | Qt.AlignBottom
//                        Layout.preferredHeight:45
//                        Layout.preferredWidth:80
//                        Button {
//                            anchors.fill: parent
//                            text: "back"
//                            onClicked: {
//                                hideDialog()
//                                showPresetSelectDialog()
////                                mapFitFunctions.fitMapViewportToMissionItems()
//                                loaded = false
////                                _planMasterController.upload()
//                            }
//                        }
//                    }
//                    Item{
//                        Layout.fillWidth: true
//                    }

//                    Rectangle {
//                        Layout.alignment: Qt.AlignRight | Qt.AlignBottom
//                        Layout.preferredHeight:45
//                        Layout.preferredWidth:80
//                        Button {
//                            anchors.fill: parent
//                            text: "confirm"
//                            onClicked: {
//                                hideDialog()
//                                showAltitudeProfile(true)
//                                mapFitFunctions.fitMapViewportToMissionItems()
//                                loaded = false
//                                altitudeProfile.update()
////                                _planMasterController.upload()
//                            }
//                        }
//                    }
//                }
//            }
//        }
//    }
    Connections{
        target:_missionController
        function updateSession(item,index){
            let x = _visualItems.get(item.index)
            if(item.preset){
//                console.log("session",item.preset.coordinate,x.coordinate)
                console.log("backend:",x.coordinate.latitude,x.coordinate.longitude)
                console.log("preset:",item.preset.coordinate.latitude,item.preset.coordinate.longitude)
                let preset = session.model[index].preset
                console.log("session model:",preset.coordinate.latitude,preset.coordinate.longitude);
                item.preset.coordinate.latitude = x.coordinate.latitude.toFixed(_decimalPlaces-1)
                item.preset.coordinate.longitude = x.coordinate.longitude.toFixed(_decimalPlaces-1)

//                item.preset.coordinate.latitude = x.coordinate.latitude.toFixed(_decimalPlaces-1)
//                item.preset.coordinate.longitude = x.coordinate.longitude.toFixed(_decimalPlaces-1)
                item.preset.coordinate.altitude = x.altitude.value
            }
        }
        function onRecalcTerrainProfile(){
            for(let i=0;i<_visualItems.count;i++){
                let item = _visualItems.get(i)
                if(i===1){
                    item.coordinate.latitude = item.launchCoordinate.latitude
                    item.coordinate.longitude = item.launchCoordinate.longitude

                }
            }

//            altitudeProfile.update()
            if(session.model){
                session.model.forEach(updateSession)
            }
        }
    }
    Timer {
        id:             _altitudeProfiletimer
        interval:       500
        repeat: true
        running: _altitudeProfile.visible
        onTriggered: {
            altitudeProfile.update()
//           showFlyView()
            //missionStats.visible = true
            //uploadCompleteText.visible = false
        }
    }

    AltitudeGraph {
        id:altitudeProfile
        height:200
        width:600
        anchors.margins:    _toolsMargin
//        anchors.leftMargin: 0
//        anchors.left: parent.left
        anchors.right:      parent.right
        anchors.top:     parent.top
        anchors.topMargin: 50
        lineseries.name: "Altitude"
        lineseries.color: "#e39414"
        lineseries.width: 3
        labelColor:"#fff"
        missionController: _missionController
    }
    Rectangle {
        id:presetNav
        height:60
        width:300
        color: qgcPal.windowShadeDark
        visible: altitudeProfile.visible && globals.toolSelectMode
        radius: 10
        anchors.margins:    _toolsMargin
//        anchors.leftMargin: 0
//        anchors.left: parent.left
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom:     parent.bottom
        RowLayout {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                Layout.alignment: Qt.AlignCenter
                Layout.preferredHeight:45
                Layout.preferredWidth:80
                Button {
                    anchors.fill: parent
                    text: "Back"
                    onClicked: {
                        showPresetEditDialog();
                    }
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignCenter
                Layout.preferredHeight:45
                Layout.preferredWidth:80
                Button {
                    anchors.fill: parent
                    text: "Upload"
                    onClicked: {
                        _planMasterController.upload()
                    }
                }
            }
        }
    }
    TerrainStatus {
        id:                 _altitudeProfile
        anchors.margins:    _toolsMargin
        anchors.left:       parent.left
//        anchors.top:        parent.top
        z:                  QGroundControl.zOrderWidgets
        anchors.leftMargin: 0
        anchors.right:      parent.right
        anchors.bottom:     parent.bottom
        height:             ScreenTools.defaultFontPixelHeight * 7
        missionController:  _missionController
        visible:            false//_internalVisible && _editingLayer === _layerMission && QGroundControl.corePlugin.options.showMissionStatus && !globals.toolSelectMode

        onSetCurrentSeqNum: _missionController.setCurrentPlanViewSeqNum(seqNum, true)

//        property bool _internalVisible: _planViewSettings.showMissionItemStatus.rawValue

        function toggleVisible() {
            _internalVisible = !_internalVisible
            _planViewSettings.showMissionItemStatus.rawValue = _internalVisible
        }
    }
}

/*##^##
Designer {
    D{i:0;autoSize:true;formeditorZoom:1.5;height:480;width:640}D{i:1}D{i:2}D{i:3}D{i:5}
D{i:11}D{i:13}D{i:14}D{i:16}D{i:17}D{i:18}D{i:19}D{i:25}D{i:47}D{i:58}D{i:60}D{i:62}
D{i:65}D{i:66}D{i:64}D{i:67}D{i:68}D{i:63}D{i:69}D{i:61}D{i:74}D{i:73}D{i:76}D{i:77}
D{i:78}D{i:59}D{i:79}D{i:80}D{i:24}D{i:81}D{i:83}D{i:85}D{i:87}D{i:89}D{i:91}D{i:96}
D{i:117}
}
##^##*/
