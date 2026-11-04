import { useEffect, useState } from "react";

import {
  ApiError,
  getUserCoupons,
  type CouponDrawResult,
  type CouponStatus,
  type UserCouponDraw,
  type UserCouponRow,
  type UserCoupons,
} from "../api";
import SortTh, { useSort } from "../components/SortTh";

type Tab = "held" | "used" | "draws";

const TAB_LABEL: Record<Tab, string> = {
  held: "보유 중인 쿠폰",
  used: "쿠폰 사용 이력",
  draws: "쿠폰 추첨 이력",
};

const STATUS_LABEL: Record<CouponStatus, string> = {
  available: "사용 가능",
  used: "사용완료",
  expired: "만료",
};

const STATUS_BADGE: Record<CouponStatus, string> = {
  available: "live",
  used: "scheduled",
  expired: "expired",
};

const RESULT_LABEL: Record<CouponDrawResult, string> = {
  won: "당첨",
  lost: "낙첨",
  sold_out: "재고 소진",
};

const RESULT_BADGE: Record<CouponDrawResult, string> = {
  won: "live",
  lost: "expired",
  sold_out: "scheduled",
};

/** grant_key → 사람이 읽는 출처. 'course:…' 같은 접두어로 가른다. 수동 지급은 null. */
function sourceLabel(grantKey: string | null): string {
  if (grantKey == null) return "운영자 지급";
  if (grantKey.startsWith("course:")) return "코스 완주";
  if (grantKey.startsWith("bingo_lines:"))
    return `빙고 ${grantKey.split(":")[2]}줄`;
  if (grantKey.startsWith("bingo:")) return "빙고판 완성";
  return grantKey;
}

interface Props {
  userId: string;
  onUnauthorized: () => void;
}

/** 회원 상세 팝업의 쿠폰 섹션. 폴더 탭 3개(보유/사용 이력/추첨 이력)로 나눠 보여준다. */
export default function UserCouponSection({ userId, onUnauthorized }: Props) {
  const [tab, setTab] = useState<Tab>("held");
  const [data, setData] = useState<UserCoupons | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let stale = false;
    setData(null);
    setError(null);
    getUserCoupons(userId)
      .then((result) => {
        if (!stale) setData(result);
      })
      .catch((err) => {
        if (stale) return;
        if (err instanceof ApiError && err.status === 401) {
          onUnauthorized();
          return;
        }
        setError(
          err instanceof ApiError
            ? err.message
            : "쿠폰 정보를 불러오지 못했어요.",
        );
      });
    return () => {
      stale = true;
    };
  }, [userId, onUnauthorized]);

  const counts: Record<Tab, number | null> = {
    held: data?.held.length ?? null,
    used: data?.used.length ?? null,
    draws: data?.draws.length ?? null,
  };

  return (
    <>
      <h3>쿠폰</h3>
      <div className="folder-tabs" role="tablist">
        {(Object.keys(TAB_LABEL) as Tab[]).map((key) => (
          <button
            key={key}
            type="button"
            role="tab"
            aria-selected={tab === key}
            className={tab === key ? "active" : undefined}
            onClick={() => setTab(key)}
          >
            {TAB_LABEL[key]}
            {counts[key] != null && (
              <span className="count">{counts[key]}</span>
            )}
          </button>
        ))}
      </div>
      <div className="folder-panel" role="tabpanel">
        {error && <div className="error">{error}</div>}
        {data == null && !error && <p className="muted">불러오는 중…</p>}
        {data && tab === "held" && (
          <CouponTable rows={data.held} empty="보유 중인 쿠폰이 없어요." />
        )}
        {data && tab === "used" && (
          <CouponTable rows={data.used} empty="사용한 쿠폰이 없어요." used />
        )}
        {data && tab === "draws" && <DrawTable rows={data.draws} />}
      </div>
    </>
  );
}

function DrawTable({ rows }: { rows: UserCouponDraw[] }) {
  const { sort, toggle, sorted } = useSort(rows, {
    drawn: (d) => d.drawn_at,
    coupon: (d) => d.coupon_name,
    source: (d) => sourceLabel(d.grant_key),
    result: (d) => RESULT_LABEL[d.result],
    code: (d) => d.code,
  });
  if (rows.length === 0) return <p className="muted">추첨 이력이 없어요.</p>;
  return (
    <table>
      <thead>
        <tr>
          <SortTh sortKey="drawn" sort={sort} onToggle={toggle}>
            추첨 시각
          </SortTh>
          <SortTh sortKey="coupon" sort={sort} onToggle={toggle}>
            쿠폰
          </SortTh>
          <SortTh sortKey="source" sort={sort} onToggle={toggle}>
            조건
          </SortTh>
          <SortTh sortKey="result" sort={sort} onToggle={toggle}>
            결과
          </SortTh>
          <SortTh sortKey="code" sort={sort} onToggle={toggle}>
            코드
          </SortTh>
        </tr>
      </thead>
      <tbody>
        {sorted!.map((d) => (
          <tr key={d.id}>
            <td className="muted nowrap">{formatDateTime(d.drawn_at)}</td>
            <td>{d.coupon_name}</td>
            <td className="muted">{sourceLabel(d.grant_key)}</td>
            <td>
              <span className={`badge ${RESULT_BADGE[d.result]}`}>
                {RESULT_LABEL[d.result]}
              </span>
            </td>
            <td className="nowrap">{d.code ? <code>{d.code}</code> : "—"}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

/** 보유/사용 탭 공용 표. 사용 탭은 사용 시각·업체 칸을 더 보여준다. */
function CouponTable({
  rows,
  empty,
  used = false,
}: {
  rows: UserCouponRow[];
  empty: string;
  used?: boolean;
}) {
  const { sort, toggle, sorted } = useSort(rows, {
    coupon: (r) => r.coupon_name,
    benefit: (r) => r.benefit,
    code: (r) => r.code,
    source: (r) => sourceLabel(r.grant_key),
    issued: (r) => r.issued_at,
    usedAt: (r) => r.used_at,
    partner: (r) => r.used_partner_name,
    valid: (r) => r.valid_until,
    status: (r) => STATUS_LABEL[r.status],
  });
  if (rows.length === 0) return <p className="muted">{empty}</p>;
  const th = (key: string, label: string) => (
    <SortTh sortKey={key} sort={sort} onToggle={toggle}>
      {label}
    </SortTh>
  );
  return (
    <table>
      <thead>
        <tr>
          {th("coupon", "쿠폰")}
          {th("benefit", "혜택")}
          {th("code", "코드")}
          {th("source", "출처")}
          {th("issued", "발급일")}
          {used ? (
            <>
              {th("usedAt", "사용 시각")}
              {th("partner", "사용처")}
            </>
          ) : (
            <>
              {th("valid", "유효기간")}
              {th("status", "상태")}
            </>
          )}
        </tr>
      </thead>
      <tbody>
        {sorted!.map((r) => (
          <tr key={r.id}>
            <td>
              <strong>{r.coupon_name}</strong>
            </td>
            <td>{r.benefit}</td>
            <td className="nowrap">
              <code>{r.code}</code>
            </td>
            <td className="muted">{sourceLabel(r.grant_key)}</td>
            <td className="muted nowrap">{formatDate(r.issued_at)}</td>
            {used ? (
              <>
                <td className="muted nowrap">
                  {r.used_at ? formatDateTime(r.used_at) : "—"}
                </td>
                <td>
                  {r.used_partner_name ??
                    (r.redeem_type === "kakao_channel"
                      ? "카카오 채널 지급"
                      : "—")}
                </td>
              </>
            ) : (
              <>
                <td className="muted nowrap">
                  {r.valid_until ? formatDate(r.valid_until) : "무기한"}
                </td>
                <td>
                  <span className={`badge ${STATUS_BADGE[r.status]}`}>
                    {STATUS_LABEL[r.status]}
                  </span>
                </td>
              </>
            )}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("ko-KR", {
    timeZone: "Asia/Seoul",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
}

function formatDateTime(iso: string): string {
  return new Date(iso).toLocaleString("ko-KR", {
    timeZone: "Asia/Seoul",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}
