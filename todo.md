# UTM Guard — TODO

## 진행 중: 선택지(드롭다운) + 시트 가져오기
- [x] 빌드 에러 확인 (이미 BUILD SUCCEEDED)
- [x] OptionStore: 사용자 관리·영구 저장(UserDefaults) 선택지 (source/medium/campaign)
- [x] ManagedPickField: 드롭다운 + "새 값 추가…" (소문자/공백 정규화)
- [x] ManageOptionsView: 목록 관리 UI + 시트/CSV 가져오기 + 파일 열기
- [x] Builder의 source/medium/campaign → 드롭다운으로 교체
- [x] Linter: 파싱된 시트 값을 선택지로 등록 버튼
- [x] SheetParser: 구분자 자동감지(TSV/CSV)
- [x] RootView: "Lists" 탭 추가, environmentObject 주입

## 완료: 팀 공유 (선택지 표준화)
- [x] OptionStore: 선택지 .json 내보내기/병합(merge)
- [x] ManageOptionsView: "선택지 내보내기" / "공유 목록 가져오기" 버튼
- [x] 도입제안.md: 팀 공유를 한계 → 기능으로 갱신
- [x] README 갱신

## 완료: 실시간 동기화
- [x] OptionStore: 공유 .json 연결(보안 북마크), 2초 폴링, 양방향 합집합 병합
- [x] 피드백 루프 차단(자기 쓰기 mtime 기록), 앱 재시작 시 자동 재개
- [x] ManageOptionsView: "공유 파일에 연결" / 상태 표시 / "연결 해제"
- [x] README / 도입제안.md 갱신

## 완료: content 자동 채번 + 선택지 의미 표시
- [x] OptionStore: 캠페인별 usedContent 레지스트리 + nextContent/isContentTaken/registerContent
- [x] meanings 맵(값→의미) + seedMeanings(ig→인스타그램 등), displayLabel "의미 (값)"
- [x] meanings·usedContent를 저장 + 동기화 스냅샷에 포함(팀 전체 고유성/의미 공유)
- [x] Builder: contentField 자동 번호 버튼 + 캠페인 선택 시 자동채움 + 중복 시 복사 차단 + 복사 시 등록
- [x] ManagedPickField: "의미 (값)" 표시 + 값/의미 함께 추가
- [x] Lists 탭: 칩에 의미 표시, 값+의미 추가
- [x] 도입제안.md(중복 차단으로 격상, 5종 불가능) / README 갱신

## 메모
- .numbers 파일은 직접 파싱 불가 → 복사 붙여넣기(TSV) 또는 CSV 내보내기로 가져옴
- 동기화: 합집합 단조증가라 충돌 없음. 삭제는 미전파.
- 자동 채번은 숫자(01,02…) 기준. 다음 후보: 삭제 전파, 채번 형식 커스터마이즈
