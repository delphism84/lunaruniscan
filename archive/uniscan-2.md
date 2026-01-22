#BE
1. 디바이스는 group, devicename으로 키관리

#App
2. app ui에서는 group 하위에 devicename으로 1depth tree구조. 앱 진입 시 모두 펼쳐지게
. 우측에 바코드를 해당 디바이스로 전송(pc에 window postmsg로 키보드 입력 에뮬레이션) 여부 체크하기.
디바이스 클릭 시 해당 디바이스 전송 로그가 보이게.
바코드 전송여부 전송시각 또는 상태
3. 기본 group 'Default' 필백
4. app ui에서 result는 항상 백그라운드 task를 렌더링 하는 구조로.
최상단에는 전체 pending, uploading, coplpete 개수/상태 표시
기본 2개탭으로 [Barcode],[Image].

#PC Agent
1. 

#로컬 테스트는 192.168.1.250가 현재 PC로 be, agent 구동
앱도 이 ip로 서버 세팅
방화벽 모둔 open상태

mongodb://<user>:<password>@139.180.189.230:57018/uniscan?authSource=admin&authMechanism=SCRAM-SHA-256