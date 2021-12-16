/****************************************************************************
 *
 * (c) 2009-2020 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#include "ABAPlanCreator.h"
#include "PlanMasterController.h"
#include "MissionSettingsItem.h"
#include "FixedWingLandingComplexItem.h"

ABAPlanCreator::ABAPlanCreator(PlanMasterController* planMasterController, QObject* parent)
    : PlanCreator(planMasterController, tr("A to B to A"), QStringLiteral("/qmlimages/PlanCreator/ABPlanCreator.png"), parent)
{

}

void ABAPlanCreator::createPlan(const QGeoCoordinate& mapCenterCoord)
{
    _planMasterController->removeAll();
    VisualMissionItem* takeoffItemA = _missionController->insertTakeoffItem(mapCenterCoord, -1);//Takeoff @ A
    _missionController->insertPresetItem(mapCenterCoord,MAV_CMD_NAV_WAYPOINT,-1,true);//Waypoint B
    VisualMissionItem* landItemB = _missionController->insertPresetItem(mapCenterCoord,MAV_CMD_NAV_LAND,-1);//Land @ B
    VisualMissionItem* takeoffItemB = _missionController->insertTakeoffItem(landItemB->coordinate(), -1);//Takeoff @ B
    _missionController->insertPresetItem(mapCenterCoord,MAV_CMD_NAV_WAYPOINT,-1);//Waypoint A
    _missionController->insertPresetItem(mapCenterCoord,MAV_CMD_NAV_LAND,-1);//Land @ A
    //    _missionController->insertPresetItem(mapCenterCoord,-1,true);
    //    _missionController->setCurrentPlanViewSeqNum(takeoffItem->sequenceNumber(), true);
    takeoffItemA->setWizardMode(false);
    takeoffItemB->setWizardMode(false);
}
