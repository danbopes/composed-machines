// Performance model: STATIC (Factorio today) vs COMPOSED (proposed ComposedMachine)
// vs RUNTIME-ECS (the 2018 "divorce behaviour from entities" idea).
//
// All architectures run the same game rules through the same core functions
// (Inventory, craftCore, inserterCore, electric/burner refill). They differ only in
// object layout and dispatch, which is the thing being measured. The final world
// state is hashed; identical hashes prove they all did identical work.
//
// Two workloads: v1 (A, B, C, D) and v2, which adds optional parts that tick
// (energy output, circuit enable, trigger on finish) and compares A2, B2, D1, D2.
// See README.md, RESULTS.md and RESULTS-v2.md.

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <numeric>
#include <random>
#include <string>
#include <vector>

using i32 = int32_t;
using i64 = int64_t;
using u64 = uint64_t;

static uint32_t g_tick = 0;

// ---------------------------------------------------------------------------
// Shared game rules
// ---------------------------------------------------------------------------

enum Item : uint8_t { NONE, ORE, PLATE, GEAR, COAL, WIDGET, NITEMS };
constexpr i32 kStackSize[NITEMS] = {1, 50, 100, 100, 50, 200};
constexpr i64 kCoalJ = 4'000'000;
constexpr i64 kInserterJ = 220;  // 13.2 kW at 60 UPS
constexpr i32 kSwing = 15;
constexpr int kNetworks = 8;

struct Hasher {
  u64 h = 1469598103934665603ull;
  void add(u64 v) {
    h ^= v;
    h *= 1099511628211ull;
    h ^= h >> 29;
  }
};

// The real engine updates entities in a fixed order, so whether an inserter sees a
// product made "this tick" depends on bucket order. The three architectures here
// deliberately iterate in different orders (C is interleaved), so to make their
// results comparable bit-for-bit every slot remembers what was added/removed this
// tick: a taker cannot take items added this tick and a putter cannot reuse space
// freed this tick. With one putter and one taker per inventory (true in this
// workload) every operation then depends only on start-of-tick state.
struct Slot {
  i32 count = 0;
  i32 addedNow = 0;
  i32 removedNow = 0;
  uint32_t stamp = 0;
  uint8_t item = NONE;
};

class Inventory {
 public:
  explicit Inventory(int nslots) : slots_(nslots) {}

  i32 takeable(Item it) const {
    i32 t = 0;
    for (const Slot& s : slots_)
      if (s.item == it) t += s.count - added(s);
    return t;
  }

  i32 space(Item it) const {
    i32 t = 0;
    for (const Slot& s : slots_) {
      if (emptyNow(s))
        t += kStackSize[it];
      else if (s.item == it)
        t += kStackSize[it] - s.count - removed(s);
    }
    return t;
  }

  // What the (single) putter should believe is present: start-of-tick count plus
  // its own additions, regardless of whether the taker already ran this tick.
  i32 countForPutter(Item it) const {
    i32 t = 0;
    for (const Slot& s : slots_)
      if (s.item == it) t += s.count + removed(s);
    return t;
  }

  template <class Accept>
  Item findTakeable(Accept accept) const {
    for (const Slot& s : slots_)
      if (s.count - added(s) > 0 && accept(static_cast<Item>(s.item)))
        return static_cast<Item>(s.item);
    return NONE;
  }

  i32 take(Item it, i32 n) {
    i32 got = 0;
    for (Slot& s : slots_) {
      if (got == n) break;
      if (s.item != it) continue;
      i32 k = std::min(s.count - added(s), n - got);
      if (k <= 0) continue;
      touch(s);
      s.count -= k;
      s.removedNow += k;
      got += k;
    }
    return got;
  }

  // Matching stacks first, then empty slots, like the game.
  i32 insert(Item it, i32 n) {
    i32 put = 0;
    for (Slot& s : slots_) {
      if (put == n) break;
      if (s.item != it || emptyNow(s)) continue;
      i32 k = std::min(kStackSize[it] - s.count - removed(s), n - put);
      if (k <= 0) continue;
      touch(s);
      s.count += k;
      s.addedNow += k;
      put += k;
    }
    for (Slot& s : slots_) {
      if (put == n) break;
      if (!emptyNow(s)) continue;
      i32 k = std::min(kStackSize[it], n - put);
      touch(s);
      s.item = it;
      s.count += k;
      s.addedNow += k;
      put += k;
    }
    return put;
  }

  void preload(Item it, i32 n) {
    for (Slot& s : slots_) {
      if (n == 0) return;
      if (s.count == 0) {
        s.item = it;
        s.count = std::min(n, kStackSize[it]);
        n -= s.count;
      }
    }
  }

  void hash(Hasher& h) const {
    for (const Slot& s : slots_) {
      h.add(s.count ? s.item : 0);
      h.add(static_cast<u64>(s.count));
    }
  }
  i32 total(Item it) const {
    i32 t = 0;
    for (const Slot& s : slots_)
      if (s.item == it) t += s.count;
    return t;
  }

 private:
  static i32 added(const Slot& s) { return s.stamp == g_tick ? s.addedNow : 0; }
  static i32 removed(const Slot& s) { return s.stamp == g_tick ? s.removedNow : 0; }
  // A slot emptied this tick still belongs to its item until the tick ends.
  static bool emptyNow(const Slot& s) { return s.count == 0 && removed(s) == 0; }
  static void touch(Slot& s) {
    if (s.stamp != g_tick) {
      s.stamp = g_tick;
      s.addedNow = 0;
      s.removedNow = 0;
    }
  }

  std::vector<Slot> slots_;
};

struct Recipe {
  Item in[2];
  i32 inAmt[2];
  int nIn;
  Item out;
  i32 outAmt;
  i32 ticks;
};
static const Recipe kSmeltPlate{{ORE, NONE}, {1, 0}, 1, PLATE, 1, 64};
static const Recipe kGear{{PLATE, NONE}, {2, 0}, 1, GEAR, 1, 30};
static const Recipe kWidget{{PLATE, GEAR}, {1, 1}, 2, WIDGET, 1, 45};

// Inserter automated-insertion limit: fill a machine up to 2x the recipe amount.
inline bool recipeWants(const Recipe* r, Item it, const Inventory& dst) {
  if (!r) return true;
  for (int i = 0; i < r->nIn; ++i)
    if (r->in[i] == it) return dst.countForPutter(it) < 2 * r->inAmt[i];
  return false;
}

// Satisfaction is computed from the previous tick's total demand and applied as an
// integer ratio, so the result does not depend on the order consumers ask in.
struct ElectricNetwork {
  i64 capacity = 0, demand = 0, num = 1, den = 1;
  i64 brownoutTicks = 0;
  void endTick() {
    if (demand <= capacity) {
      num = den = 1;
    } else {
      num = capacity;
      den = demand;
      ++brownoutTicks;
    }
    demand = 0;
  }
};

inline void electricRefill(i64& buffer, i64 cap, ElectricNetwork& net) {
  i64 req = cap - buffer;
  if (req > 0) {
    net.demand += req;
    buffer += req * net.num / net.den;
  }
}
inline void burnerRefill(i64& buffer, i64 perTick, Inventory& fuel) {
  if (buffer < perTick && fuel.take(COAL, 1)) buffer += kCoalJ;
}
inline i64 takeEnergy(i64& buffer, i64 want) {
  i64 g = std::min(buffer, want);
  buffer -= g;
  return g;
}

struct CraftState {
  const Recipe* recipe = nullptr;
  i64 power = 0;  // J per tick
  i64 progress = 0;
  bool crafting = false;
  void hash(Hasher& h) const {
    h.add(static_cast<u64>(progress));
    h.add(crafting);
  }
};

// kOptional: the COMPOSED machine's parts may be absent; the static classes skip
// those checks because their type guarantees the parts exist. Returns true on the tick a
// cycle finishes, which is where the v2 energy output and trigger parts act.
template <class E, bool kOptional>
inline bool craftCore(CraftState& cs, E* energy, Inventory* in, Inventory* out) {
  const Recipe& r = *cs.recipe;
  if constexpr (kOptional) {
    if (!out || (r.nIn && !in)) return false;
  }
  if (!cs.crafting) {
    if (out->space(r.out) < r.outAmt) return false;
    for (int i = 0; i < r.nIn; ++i)
      if (in->takeable(r.in[i]) < r.inAmt[i]) return false;
    for (int i = 0; i < r.nIn; ++i) in->take(r.in[i], r.inAmt[i]);
    cs.crafting = true;
    cs.progress = 0;
  }
  const i64 need = r.ticks * cs.power;
  if (cs.progress < need) {
    i64 want = std::min(cs.power, need - cs.progress);
    i64 got;
    if constexpr (kOptional)
      got = energy ? energy->extractEnergy(want) : want;
    else
      got = energy->extractEnergy(want);
    cs.progress += got;
  }
  if (cs.progress >= need && out->space(r.out) >= r.outAmt) {
    out->insert(r.out, r.outAmt);
    cs.crafting = false;
    cs.progress = 0;
    return true;
  }
  return false;
}

enum Phase : uint8_t { PICK, TO_DROP, DROP, RETURN };
struct InserterState {
  Item hand = NONE;
  i32 handCount = 0;
  i32 handCap = 1;
  i32 timer = 0;
  uint8_t phase = PICK;
  void hash(Hasher& h) const {
    h.add(hand);
    h.add(static_cast<u64>(handCount));
    h.add(static_cast<u64>(timer));
    h.add(phase);
  }
};

template <class E>
inline void inserterCore(InserterState& st, E& energy, Inventory* src, Inventory* dst,
                         const Recipe* dstRecipe) {
  switch (st.phase) {
    case PICK: {
      Item it = src->findTakeable([&](Item i) { return recipeWants(dstRecipe, i, *dst); });
      if (it == NONE) return;
      st.hand = it;
      st.handCount = src->take(it, st.handCap);
      st.phase = TO_DROP;
      st.timer = kSwing;
      return;
    }
    case TO_DROP:
    case RETURN:
      if (st.timer > 0) {
        if (energy.extractEnergy(kInserterJ) == kInserterJ) --st.timer;
        return;
      }
      st.phase = st.phase == TO_DROP ? DROP : PICK;
      return;
    case DROP: {
      st.handCount -= dst->insert(st.hand, st.handCount);
      if (st.handCount == 0) {
        st.hand = NONE;
        st.phase = RETURN;
        st.timer = kSwing;
      }
      return;
    }
  }
}

// ---------------------------------------------------------------------------
// World layout, shared by all architectures (so the workload is identical)
// ---------------------------------------------------------------------------
// A "group" is 10 entities: 4 containers (40%), 3 inserters (30%), 3 machines (30%).
//   ore chest -> I0 -> M0 furnace (ore->plate) -> I1 -> M1 assembler (2 plate->gear)
//   -> I2 -> sink chest.  M2 assembler (plate+gear->widget) is hand-fed (preloaded
//   input, uncollected output). Spare and fuel chests are passive.
// Burner/electric alternates per group so machines are half burner, half electric.
enum Role { R_ORE, R_SINK, R_SPARE, R_FUEL, R_I0, R_I1, R_I2, R_M0, R_M1, R_M2, kRoles };
static const Recipe* const kMachineRecipe[3] = {&kSmeltPlate, &kGear, &kWidget};
constexpr i64 kMachinePower[3] = {1500, 2500, 2500};
constexpr int kMachineInSlots[3] = {1, 2, 2};
constexpr i32 kHandCap[3] = {1, 1, 2};

inline bool isBurner(size_t g, int k) { return (g % 2 == 0) ? (k != 1) : (k == 1); }
inline u64 rnd(u64 seed, size_t g, int role) {
  u64 z = seed + (g * kRoles + role + 1) * 0x9E3779B97F4A7C15ull;
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
  return z ^ (z >> 31);
}
inline size_t netOf(size_t g, size_t G) { return g * kNetworks / G; }

std::vector<ElectricNetwork> makeNetworks(size_t G) {
  std::vector<ElectricNetwork> nets(kNetworks);
  for (size_t g = 0; g < G; ++g) {
    i64 peak = 3 * kInserterJ;
    for (int k = 0; k < 3; ++k)
      if (!isBurner(g, k)) peak += kMachinePower[k];
    nets[netOf(g, G)].capacity += peak;
  }
  // Every fourth network is undersized so the brownout path is exercised.
  for (int n = 0; n < kNetworks; ++n)
    nets[n].capacity = nets[n].capacity * (n % 4 == 3 ? 4 : 16) / 10;
  return nets;
}

std::unique_ptr<Inventory> makeChest(int role) {
  switch (role) {
    case R_ORE: {
      auto inv = std::make_unique<Inventory>(12);
      inv->preload(ORE, 400);
      return inv;
    }
    case R_SINK:
      return std::make_unique<Inventory>(16);
    case R_SPARE: {
      auto inv = std::make_unique<Inventory>(8);
      inv->preload(WIDGET, 600);
      return inv;
    }
    default: {
      auto inv = std::make_unique<Inventory>(8);
      inv->preload(COAL, 200);
      return inv;
    }
  }
}
std::unique_ptr<Inventory> makeMachineInput(int k) {
  auto inv = std::make_unique<Inventory>(kMachineInSlots[k]);
  if (k == 2) {
    inv->preload(PLATE, 50);
    inv->preload(GEAR, 50);
  }
  return inv;
}
std::unique_ptr<Inventory> makeFuel() {
  auto inv = std::make_unique<Inventory>(1);
  inv->preload(COAL, 5);
  return inv;
}
CraftState makeCraftState(u64 seed, size_t g, int k) {
  CraftState cs;
  cs.recipe = kMachineRecipe[k];
  cs.power = kMachinePower[k];
  if (k == 2) {  // stagger the hand-fed machines so they don't tick in lockstep
    cs.crafting = true;
    cs.progress = static_cast<i64>(rnd(seed, g, R_M2) % (kWidget.ticks * cs.power));
  }
  return cs;
}
InserterState makeInserterState(u64 seed, size_t g, int j) {
  InserterState st;
  st.handCap = kHandCap[j];
  st.phase = RETURN;
  st.timer = static_cast<i32>(rnd(seed, g, R_I0 + j) % kSwing);
  return st;
}
i64 burnerStart(u64 seed, size_t g, int k) {
  return static_cast<i64>(rnd(seed ^ 0xABCD, g, R_M0 + k) % kCoalJ);
}

// Entities are allocated in shuffled order so iteration (which is in group order)
// chases pointers across the heap, like an active list built up over a long game.
std::vector<size_t> shuffledOrder(size_t n, u64 seed) {
  std::vector<size_t> v(n);
  std::iota(v.begin(), v.end(), size_t{0});
  std::mt19937_64 rng(seed);
  std::shuffle(v.begin(), v.end(), rng);
  return v;
}

struct Stats {
  i64 gearsInSinks = 0, widgets = 0, coalInBurners = 0, brownoutTicks = 0;
  // v2 workload only
  i64 energyGenerated = 0, triggersFired = 0, disabledAtEnd = 0;
};

// ---------------------------------------------------------------------------
// Energy sources: polymorphic component, as in the real engine (A and B share it)
// ---------------------------------------------------------------------------
class EnergySource {
 public:
  virtual ~EnergySource() = default;
  virtual void update() = 0;
  virtual i64 extractEnergy(i64 want) = 0;
  virtual void hash(Hasher& h) const = 0;
  virtual i64 fuelCount() const { return 0; }
};

class ElectricEnergySource final : public EnergySource {
 public:
  ElectricEnergySource(ElectricNetwork* net, i64 perTick) : net_(net), cap_(2 * perTick) {}
  void update() override { electricRefill(buffer_, cap_, *net_); }
  i64 extractEnergy(i64 want) override { return takeEnergy(buffer_, want); }
  void hash(Hasher& h) const override { h.add(static_cast<u64>(buffer_)); }

 private:
  ElectricNetwork* net_;
  i64 cap_;
  i64 buffer_ = 0;
};

class BurnerEnergySource final : public EnergySource {
 public:
  BurnerEnergySource(i64 perTick, i64 start) : fuel_(makeFuel()), perTick_(perTick), buffer_(start) {}
  void update() override { burnerRefill(buffer_, perTick_, *fuel_); }
  i64 extractEnergy(i64 want) override { return takeEnergy(buffer_, want); }
  void hash(Hasher& h) const override {
    h.add(static_cast<u64>(buffer_));
    fuel_->hash(h);
  }
  i64 fuelCount() const override { return fuel_->total(COAL); }

 private:
  std::unique_ptr<Inventory> fuel_;
  i64 perTick_;
  i64 buffer_;
};

std::unique_ptr<EnergySource> makeMachineEnergy(u64 seed, size_t g, int k, ElectricNetwork* net) {
  if (isBurner(g, k))
    return std::make_unique<BurnerEnergySource>(kMachinePower[k], burnerStart(seed, g, k));
  return std::make_unique<ElectricEnergySource>(net, kMachinePower[k]);
}

// ---------------------------------------------------------------------------
// Entity base (A and B). Inserters reach their targets through these virtuals in
// both, because a real inserter can target any entity type.
// ---------------------------------------------------------------------------
class UpdatableEntity;
class Entity {
 public:
  virtual ~Entity() = default;
  virtual UpdatableEntity* asUpdatableEntity() { return nullptr; }
  virtual Inventory* pickupInventory() { return nullptr; }
  virtual Inventory* dropInventory() { return nullptr; }
  virtual const Recipe* dropRecipe() const { return nullptr; }
};
class UpdatableEntity : public Entity {
 public:
  UpdatableEntity* asUpdatableEntity() override { return this; }
  virtual void update() = 0;
};

class Inserter final : public UpdatableEntity {
 public:
  Inserter(ElectricNetwork* net, InserterState st)
      : energy_(std::make_unique<ElectricEnergySource>(net, kInserterJ)), st_(st) {}
  void update() override {
    energy_->update();
    inserterCore(st_, *energy_, pickup->pickupInventory(), drop->dropInventory(), drop->dropRecipe());
  }
  void hash(Hasher& h) const {
    st_.hash(h);
    energy_->hash(h);
  }
  Entity* pickup = nullptr;
  Entity* drop = nullptr;

 private:
  // Held through the base pointer on purpose: the real engine dispatches
  // EnergySource::update virtually, and this model should pay the same.
  std::unique_ptr<EnergySource> energy_;
  InserterState st_;
};

// ---------------------------------------------------------------------------
// A. STATIC: Container / Furnace / AssemblingMachine (+ Inserter), type-bucketed
// ---------------------------------------------------------------------------
namespace arch_static {

class Container final : public Entity {
 public:
  explicit Container(std::unique_ptr<Inventory> inv) : inv_(std::move(inv)) {}
  Inventory* pickupInventory() override { return inv_.get(); }
  Inventory* dropInventory() override { return inv_.get(); }
  const Inventory& inv() const { return *inv_; }

 private:
  std::unique_ptr<Inventory> inv_;
};

class CraftingMachine : public UpdatableEntity {
 public:
  CraftingMachine(std::unique_ptr<EnergySource> e, std::unique_ptr<Inventory> in, CraftState cs)
      : energy_(std::move(e)), in_(std::move(in)), out_(std::make_unique<Inventory>(1)), cs_(cs) {}
  void update() override {
    energy_->update();
    craftCore<EnergySource, false>(cs_, energy_.get(), in_.get(), out_.get());
  }
  Inventory* pickupInventory() override { return out_.get(); }
  Inventory* dropInventory() override { return in_.get(); }
  const Recipe* dropRecipe() const override { return cs_.recipe; }
  void hash(Hasher& h, Stats& s) const {
    in_->hash(h);
    out_->hash(h);
    energy_->hash(h);
    cs_.hash(h);
    s.widgets += out_->total(WIDGET);
    s.coalInBurners += energy_->fuelCount();
  }

 private:
  std::unique_ptr<EnergySource> energy_;
  std::unique_ptr<Inventory> in_, out_;
  CraftState cs_;
};
class Furnace final : public CraftingMachine {
  using CraftingMachine::CraftingMachine;
};
class AssemblingMachine final : public CraftingMachine {
  using CraftingMachine::CraftingMachine;
};

struct World {
  std::vector<ElectricNetwork> nets;
  std::vector<Entity*> table;  // [g * kRoles + role], for wiring and hashing only
  // Per-type buckets, updated in the engine's per-type update list order.
  std::vector<Inserter*> inserters;
  std::vector<AssemblingMachine*> assemblers;
  std::vector<Furnace*> furnaces;
  size_t G = 0;

  Entity* create(u64 seed, size_t g, int role) {
    ElectricNetwork* net = &nets[netOf(g, G)];
    if (role <= R_FUEL) return new Container(makeChest(role));
    if (role <= R_I2) return new Inserter(net, makeInserterState(seed, g, role - R_I0));
    int k = role - R_M0;
    auto e = makeMachineEnergy(seed, g, k, net);
    auto in = makeMachineInput(k);
    if (k == 0) return new Furnace(std::move(e), std::move(in), makeCraftState(seed, g, k));
    return new AssemblingMachine(std::move(e), std::move(in), makeCraftState(seed, g, k));
  }

  void build(size_t groups, u64 seed) {
    G = groups;
    nets = makeNetworks(G);
    table.assign(G * kRoles, nullptr);
    for (size_t idx : shuffledOrder(table.size(), seed)) table[idx] = create(seed, idx / kRoles, idx % kRoles);
    for (size_t g = 0; g < G; ++g) {
      Entity** t = &table[g * kRoles];
      auto wire = [&](int ins, int from, int to) {
        auto* i = static_cast<Inserter*>(t[ins]);
        i->pickup = t[from];
        i->drop = t[to];
        inserters.push_back(i);
      };
      wire(R_I0, R_ORE, R_M0);
      wire(R_I1, R_M0, R_M1);
      wire(R_I2, R_M1, R_SINK);
      furnaces.push_back(static_cast<Furnace*>(t[R_M0]));
      assemblers.push_back(static_cast<AssemblingMachine*>(t[R_M1]));
      assemblers.push_back(static_cast<AssemblingMachine*>(t[R_M2]));
    }
  }

  void tick() {
    ++g_tick;
    // Qualified calls = static dispatch per bucket, as the templated
    // the engine's per-type update loop does in the real engine.
    for (Inserter* e : inserters) e->Inserter::update();
    for (AssemblingMachine* e : assemblers) e->AssemblingMachine::update();
    for (Furnace* e : furnaces) e->Furnace::update();
    for (ElectricNetwork& n : nets) n.endTick();
  }

  u64 checksum(Stats& s) const {
    Hasher h;
    for (const ElectricNetwork& n : nets) s.brownoutTicks += n.brownoutTicks;
    for (size_t g = 0; g < G; ++g) {
      Entity* const* t = &table[g * kRoles];
      for (int r = R_ORE; r <= R_FUEL; ++r) static_cast<Container*>(t[r])->inv().hash(h);
      s.gearsInSinks += static_cast<Container*>(t[R_SINK])->inv().total(GEAR);
      for (int r = R_I0; r <= R_I2; ++r) static_cast<Inserter*>(t[r])->hash(h);
      for (int r = R_M0; r <= R_M2; ++r) static_cast<CraftingMachine*>(t[r])->hash(h, s);
    }
    return h.h;
  }
  size_t active() const { return inserters.size() + assemblers.size() + furnaces.size(); }
  ~World() {
    for (Entity* e : table) delete e;
  }
};

}  // namespace arch_static

// ---------------------------------------------------------------------------
// B. COMPOSED: one static class whose parts are fixed at construction
// ---------------------------------------------------------------------------
namespace arch_composed {

struct FluidBox {  // optional part; present in the layout, unused by this workload
  i64 amount = 0;
  void update() {}
};

class ComposedMachine final : public Entity {
 public:
  enum Part : uint8_t { kInput = 1, kOutput = 2, kTimer = 4, kEnergy = 8, kFluid = 16 };

  ComposedMachine(uint8_t parts, std::unique_ptr<EnergySource> e, std::unique_ptr<Inventory> in,
                  std::unique_ptr<Inventory> out, CraftState cs)
      : parts_(parts), energy_(std::move(e)), in_(std::move(in)), out_(std::move(out)), cs_(cs) {}

  // Instances with no ticking part never enter the active list.
  bool ticks() const { return parts_ & (kTimer | kEnergy | kFluid); }

  void update() {
    if (energy_) energy_->update();
    if (parts_ & kTimer) craftCore<EnergySource, true>(cs_, energy_.get(), in_.get(), out_.get());
    if (fluid_) fluid_->update();
  }

  Inventory* pickupInventory() override { return out_.get(); }
  Inventory* dropInventory() override { return in_ ? in_.get() : out_.get(); }
  const Recipe* dropRecipe() const override { return (parts_ & kTimer) ? cs_.recipe : nullptr; }

  void hash(Hasher& h, Stats& s) const {
    if (in_) in_->hash(h);
    if (out_) out_->hash(h);
    if (energy_) energy_->hash(h);
    if (parts_ & kTimer) cs_.hash(h);
    if (out_) s.widgets += (parts_ & kTimer) ? out_->total(WIDGET) : 0;
    if (energy_) s.coalInBurners += energy_->fuelCount();
  }
  const Inventory* storage() const { return out_.get(); }

 private:
  uint8_t parts_;
  std::unique_ptr<EnergySource> energy_;
  std::unique_ptr<Inventory> in_, out_;
  std::unique_ptr<FluidBox> fluid_;
  CraftState cs_;
};

struct World {
  std::vector<ElectricNetwork> nets;
  std::vector<Entity*> table;
  std::vector<Inserter*> inserters;
  std::vector<ComposedMachine*> composed;
  size_t G = 0;

  Entity* create(u64 seed, size_t g, int role) {
    using CM = ComposedMachine;
    ElectricNetwork* net = &nets[netOf(g, G)];
    if (role <= R_FUEL) return new CM(CM::kOutput, nullptr, nullptr, makeChest(role), CraftState{});
    if (role <= R_I2) return new Inserter(net, makeInserterState(seed, g, role - R_I0));
    int k = role - R_M0;
    auto e = makeMachineEnergy(seed, g, k, net);
    auto in = makeMachineInput(k);
    return new CM(CM::kInput | CM::kOutput | CM::kTimer | CM::kEnergy, std::move(e), std::move(in),
                  std::make_unique<Inventory>(1), makeCraftState(seed, g, k));
  }

  void build(size_t groups, u64 seed) {
    G = groups;
    nets = makeNetworks(G);
    table.assign(G * kRoles, nullptr);
    for (size_t idx : shuffledOrder(table.size(), seed)) table[idx] = create(seed, idx / kRoles, idx % kRoles);
    for (size_t g = 0; g < G; ++g) {
      Entity** t = &table[g * kRoles];
      auto wire = [&](int ins, int from, int to) {
        auto* i = static_cast<Inserter*>(t[ins]);
        i->pickup = t[from];
        i->drop = t[to];
        inserters.push_back(i);
      };
      wire(R_I0, R_ORE, R_M0);
      wire(R_I1, R_M0, R_M1);
      wire(R_I2, R_M1, R_SINK);
      for (int r : {R_ORE, R_SINK, R_SPARE, R_FUEL, R_M0, R_M1, R_M2}) {
        auto* m = static_cast<ComposedMachine*>(t[r]);
        if (m->ticks()) composed.push_back(m);
      }
    }
  }

  void tick() {
    ++g_tick;
    for (Inserter* e : inserters) e->Inserter::update();
    for (ComposedMachine* e : composed) e->update();
    for (ElectricNetwork& n : nets) n.endTick();
  }

  u64 checksum(Stats& s) const {
    Hasher h;
    for (const ElectricNetwork& n : nets) s.brownoutTicks += n.brownoutTicks;
    for (size_t g = 0; g < G; ++g) {
      Entity* const* t = &table[g * kRoles];
      for (int r = R_ORE; r <= R_FUEL; ++r) static_cast<ComposedMachine*>(t[r])->hash(h, s);
      s.gearsInSinks += static_cast<ComposedMachine*>(t[R_SINK])->storage()->total(GEAR);
      for (int r = R_I0; r <= R_I2; ++r) static_cast<Inserter*>(t[r])->hash(h);
      for (int r = R_M0; r <= R_M2; ++r) static_cast<ComposedMachine*>(t[r])->hash(h, s);
    }
    return h.h;
  }
  size_t active() const { return inserters.size() + composed.size(); }
  ~World() {
    for (Entity* e : table) delete e;
  }
};

}  // namespace arch_composed

// ---------------------------------------------------------------------------
// C. RUNTIME-ECS: entity = vector<Component*>, heterogeneous virtual update.
// Components find their siblings and their targets' components by tag at use
// time; caching those pointers would reintroduce the static wiring this design
// was meant to remove.
// ---------------------------------------------------------------------------
namespace arch_ecs {

enum Tag : uint8_t { T_INV_IN, T_INV_OUT, T_INV_FUEL, T_INV_STORAGE, T_ENERGY, T_CRAFTER, T_INSERTER };

struct CEntity;
struct Component {
  Component(CEntity* o, Tag t) : owner(o), tag(t) {}
  virtual ~Component() = default;
  virtual void update() {}
  CEntity* owner;
  Tag tag;
};

struct CEntity {
  std::vector<Component*> comps;
  Component* get(Tag t) const {
    for (Component* c : comps)
      if (c->tag == t) return c;
    return nullptr;
  }
  template <class T>
  T* as(Tag t) const {
    return static_cast<T*>(get(t));
  }
  ~CEntity() {
    for (Component* c : comps) delete c;
  }
};

struct InventoryComponent final : Component {
  InventoryComponent(CEntity* o, Tag t, std::unique_ptr<Inventory> i) : Component(o, t), inv(std::move(i)) {}
  std::unique_ptr<Inventory> inv;
};

struct EnergyComponent : Component {
  using Component::Component;
  virtual i64 extractEnergy(i64 want) = 0;
  i64 buffer = 0;
};
struct ElectricComponent final : EnergyComponent {
  ElectricComponent(CEntity* o, ElectricNetwork* n, i64 perTick) : EnergyComponent(o, T_ENERGY), net(n), cap(2 * perTick) {}
  void update() override { electricRefill(buffer, cap, *net); }
  i64 extractEnergy(i64 want) override { return takeEnergy(buffer, want); }
  ElectricNetwork* net;
  i64 cap;
};
struct BurnerComponent final : EnergyComponent {
  BurnerComponent(CEntity* o, i64 pt, i64 start) : EnergyComponent(o, T_ENERGY), perTick(pt) { buffer = start; }
  void update() override { burnerRefill(buffer, perTick, *owner->as<InventoryComponent>(T_INV_FUEL)->inv); }
  i64 extractEnergy(i64 want) override { return takeEnergy(buffer, want); }
  i64 perTick;
};

struct CrafterComponent final : Component {
  CrafterComponent(CEntity* o, CraftState c) : Component(o, T_CRAFTER), cs(c) {}
  void update() override {
    auto* e = owner->as<EnergyComponent>(T_ENERGY);
    auto* in = owner->as<InventoryComponent>(T_INV_IN);
    auto* out = owner->as<InventoryComponent>(T_INV_OUT);
    craftCore<EnergyComponent, false>(cs, e, in->inv.get(), out->inv.get());
  }
  CraftState cs;
};

inline Inventory* findInv(CEntity* e, Tag preferred) {
  Component* c = e->get(preferred);
  if (!c) c = e->get(T_INV_STORAGE);
  return static_cast<InventoryComponent*>(c)->inv.get();
}

struct InserterComponent final : Component {
  InserterComponent(CEntity* o, InserterState s) : Component(o, T_INSERTER), st(s) {}
  void update() override {
    auto* e = owner->as<EnergyComponent>(T_ENERGY);
    auto* crafter = drop->as<CrafterComponent>(T_CRAFTER);
    inserterCore(st, *e, findInv(pickup, T_INV_OUT), findInv(drop, T_INV_IN), crafter ? crafter->cs.recipe : nullptr);
  }
  CEntity* pickup = nullptr;
  CEntity* drop = nullptr;
  InserterState st;
};

struct World {
  std::vector<ElectricNetwork> nets;
  std::vector<CEntity*> table;
  std::vector<CEntity*> active_;  // one heterogeneous list, in group (spatial) order
  size_t G = 0;

  CEntity* create(u64 seed, size_t g, int role) {
    ElectricNetwork* net = &nets[netOf(g, G)];
    auto* e = new CEntity;
    auto add = [&](Component* c) { e->comps.push_back(c); };
    if (role <= R_FUEL) {
      add(new InventoryComponent(e, T_INV_STORAGE, makeChest(role)));
    } else if (role <= R_I2) {
      add(new ElectricComponent(e, net, kInserterJ));
      add(new InserterComponent(e, makeInserterState(seed, g, role - R_I0)));
    } else {
      int k = role - R_M0;
      bool burner = isBurner(g, k);
      if (burner)
        add(new BurnerComponent(e, kMachinePower[k], burnerStart(seed, g, k)));
      else
        add(new ElectricComponent(e, net, kMachinePower[k]));
      add(new InventoryComponent(e, T_INV_IN, makeMachineInput(k)));
      add(new InventoryComponent(e, T_INV_OUT, std::make_unique<Inventory>(1)));
      if (burner) add(new InventoryComponent(e, T_INV_FUEL, makeFuel()));
      add(new CrafterComponent(e, makeCraftState(seed, g, k)));
    }
    return e;
  }

  void build(size_t groups, u64 seed) {
    G = groups;
    nets = makeNetworks(G);
    table.assign(G * kRoles, nullptr);
    for (size_t idx : shuffledOrder(table.size(), seed)) table[idx] = create(seed, idx / kRoles, idx % kRoles);
    for (size_t g = 0; g < G; ++g) {
      CEntity** t = &table[g * kRoles];
      auto wire = [&](int ins, int from, int to) {
        auto* i = t[ins]->as<InserterComponent>(T_INSERTER);
        i->pickup = t[from];
        i->drop = t[to];
      };
      wire(R_I0, R_ORE, R_M0);
      wire(R_I1, R_M0, R_M1);
      wire(R_I2, R_M1, R_SINK);
      // Chests have no ticking component, so (generously to this design) they are
      // left out of the active list just as in A and B.
      for (int r = R_I0; r <= R_M2; ++r) active_.push_back(t[r]);
    }
  }

  void tick() {
    ++g_tick;
    for (CEntity* e : active_)
      for (Component* c : e->comps) c->update();
    for (ElectricNetwork& n : nets) n.endTick();
  }

  // Must visit state in exactly the order the A/B hash functions do.
  u64 checksum(Stats& s) const {
    Hasher h;
    for (const ElectricNetwork& n : nets) s.brownoutTicks += n.brownoutTicks;
    for (size_t g = 0; g < G; ++g) {
      CEntity* const* t = &table[g * kRoles];
      for (int r = R_ORE; r <= R_FUEL; ++r) t[r]->as<InventoryComponent>(T_INV_STORAGE)->inv->hash(h);
      s.gearsInSinks += t[R_SINK]->as<InventoryComponent>(T_INV_STORAGE)->inv->total(GEAR);
      for (int r = R_I0; r <= R_I2; ++r) {
        t[r]->as<InserterComponent>(T_INSERTER)->st.hash(h);
        h.add(static_cast<u64>(t[r]->as<EnergyComponent>(T_ENERGY)->buffer));
      }
      for (int r = R_M0; r <= R_M2; ++r) {
        CEntity* m = t[r];
        m->as<InventoryComponent>(T_INV_IN)->inv->hash(h);
        Inventory* out = m->as<InventoryComponent>(T_INV_OUT)->inv.get();
        out->hash(h);
        h.add(static_cast<u64>(m->as<EnergyComponent>(T_ENERGY)->buffer));
        if (auto* fuel = m->as<InventoryComponent>(T_INV_FUEL)) {
          fuel->inv->hash(h);
          s.coalInBurners += fuel->inv->total(COAL);
        }
        m->as<CrafterComponent>(T_CRAFTER)->cs.hash(h);
        s.widgets += out->total(WIDGET);
      }
    }
    return h.h;
  }
  size_t active() const { return active_.size(); }
  ~World() {
    for (CEntity* e : table) delete e;
  }
};

}  // namespace arch_ecs

// ---------------------------------------------------------------------------
// D. TEMPLATED COMPOSED: same proposal as B, but each part shape is its own
// template instantiation. An absent part is an empty base (zero bytes via the
// empty-base optimisation) and its check is removed by if constexpr, so a
// chest-shaped instance is laid out exactly like arch_static::Container.
// ---------------------------------------------------------------------------
namespace arch_templated {

template <bool> struct InputPart {};
template <> struct InputPart<true> { std::unique_ptr<Inventory> in; };
template <bool> struct EnergyPart {};
template <> struct EnergyPart<true> { std::unique_ptr<EnergySource> energy; };
template <bool> struct TimerPart {};
template <> struct TimerPart<true> { CraftState cs; };
template <bool> struct FluidPart {};
template <> struct FluidPart<true> { std::unique_ptr<arch_composed::FluidBox> fluid; };

struct NoEnergy {  // a timer without an energy part runs for free
  i64 extractEnergy(i64 want) { return want; }
};

template <bool Input, bool Energy, bool Timer, bool Fluid>
class Composed final : public Entity,
                       public InputPart<Input>,
                       public EnergyPart<Energy>,
                       public TimerPart<Timer>,
                       public FluidPart<Fluid> {
 public:
  static constexpr bool kTicks = Energy || Timer || Fluid;

  explicit Composed(std::unique_ptr<Inventory> out) : out_(std::move(out)) {}

  void update() {
    if constexpr (Energy) this->energy->update();
    if constexpr (Timer) {
      Inventory* in = nullptr;
      if constexpr (Input) in = this->in.get();
      if constexpr (Energy) {
        craftCore<EnergySource, false>(this->cs, this->energy.get(), in, out_.get());
      } else {
        NoEnergy free;
        craftCore<NoEnergy, false>(this->cs, &free, in, out_.get());
      }
    }
    if constexpr (Fluid) this->fluid->update();
  }

  Inventory* pickupInventory() override { return out_.get(); }
  Inventory* dropInventory() override {
    if constexpr (Input) return this->in.get();
    return out_.get();
  }
  const Recipe* dropRecipe() const override {
    if constexpr (Timer) return this->cs.recipe;
    return nullptr;
  }

  // Same visiting order as arch_composed::ComposedMachine::hash.
  void hash(Hasher& h, Stats& s) const {
    if constexpr (Input) this->in->hash(h);
    out_->hash(h);
    if constexpr (Energy) {
      this->energy->hash(h);
      s.coalInBurners += this->energy->fuelCount();
    }
    if constexpr (Timer) {
      this->cs.hash(h);
      s.widgets += out_->total(WIDGET);
    }
  }
  const Inventory* storage() const { return out_.get(); }

 private:
  std::unique_ptr<Inventory> out_;
};

using ChestShape = Composed<false, false, false, false>;
using MachineShape = Composed<true, true, true, false>;
static_assert(!ChestShape::kTicks && MachineShape::kTicks, "shape tick flags");

struct World {
  std::vector<ElectricNetwork> nets;
  std::vector<Entity*> table;
  std::vector<Inserter*> inserters;
  // One homogeneous bucket per ticking shape; this workload has only one.
  std::vector<MachineShape*> machines;
  size_t G = 0;

  Entity* create(u64 seed, size_t g, int role) {
    ElectricNetwork* net = &nets[netOf(g, G)];
    if (role <= R_FUEL) return new ChestShape(makeChest(role));
    if (role <= R_I2) return new Inserter(net, makeInserterState(seed, g, role - R_I0));
    int k = role - R_M0;
    auto* m = new MachineShape(std::make_unique<Inventory>(1));
    m->energy = makeMachineEnergy(seed, g, k, net);
    m->in = makeMachineInput(k);
    m->cs = makeCraftState(seed, g, k);
    return m;
  }

  void build(size_t groups, u64 seed) {
    G = groups;
    nets = makeNetworks(G);
    table.assign(G * kRoles, nullptr);
    for (size_t idx : shuffledOrder(table.size(), seed)) table[idx] = create(seed, idx / kRoles, idx % kRoles);
    for (size_t g = 0; g < G; ++g) {
      Entity** t = &table[g * kRoles];
      auto wire = [&](int ins, int from, int to) {
        auto* i = static_cast<Inserter*>(t[ins]);
        i->pickup = t[from];
        i->drop = t[to];
        inserters.push_back(i);
      };
      wire(R_I0, R_ORE, R_M0);
      wire(R_I1, R_M0, R_M1);
      wire(R_I2, R_M1, R_SINK);
      for (int r = R_M0; r <= R_M2; ++r) machines.push_back(static_cast<MachineShape*>(t[r]));
    }
  }

  void tick() {
    ++g_tick;
    for (Inserter* e : inserters) e->Inserter::update();
    for (MachineShape* e : machines) e->update();
    for (ElectricNetwork& n : nets) n.endTick();
  }

  u64 checksum(Stats& s) const {
    Hasher h;
    for (const ElectricNetwork& n : nets) s.brownoutTicks += n.brownoutTicks;
    for (size_t g = 0; g < G; ++g) {
      Entity* const* t = &table[g * kRoles];
      for (int r = R_ORE; r <= R_FUEL; ++r) static_cast<ChestShape*>(t[r])->hash(h, s);
      s.gearsInSinks += static_cast<ChestShape*>(t[R_SINK])->storage()->total(GEAR);
      for (int r = R_I0; r <= R_I2; ++r) static_cast<Inserter*>(t[r])->hash(h);
      for (int r = R_M0; r <= R_M2; ++r) static_cast<MachineShape*>(t[r])->hash(h, s);
    }
    return h.h;
  }
  size_t active() const { return inserters.size() + machines.size(); }
  ~World() {
    for (Entity* e : table) delete e;
  }
};

}  // namespace arch_templated

// ===========================================================================
// v2 workload: optional parts that tick
// ===========================================================================
// Machines may also have an energy output (electric or heat, pushed on cycle
// finish), a circuit enable flag (set by a control-behaviour pass outside the
// entity update; a disabled machine skips its update), and a trigger fired on
// cycle finish. The rules below are shared by A2, B2, D1 and D2, exactly as the
// v1 rules are shared by A/B/C/D; only where the parts live and how the update
// reaches them differs. Chests and inserters are unchanged from v1.

constexpr i64 kElectricPerCycle = 40'000;
constexpr i64 kGeneratorDrain = 1'000;  // what the network draws from one buffer per tick
constexpr i64 kAmbient = 15'000;
constexpr i64 kHeatPerCycle = 50'000;
constexpr uint32_t kControlPeriod = 30;

// Virtual only so that D1 can hold either kind behind one pointer. A2, B2 and D2
// hold the final classes, so their push() calls are direct.
class EnergyOutput {
 public:
  virtual ~EnergyOutput() = default;
  virtual void push() = 0;
  virtual i64 value() const = 0;
};

class ElectricOutput final : public EnergyOutput {
 public:
  void push() override { buffer_ += kElectricPerCycle; }
  i64 value() const override { return buffer_; }
  i64 drain() {
    i64 d = std::min(buffer_, kGeneratorDrain);
    buffer_ -= d;
    return d;
  }

 private:
  i64 buffer_ = 0;
};

class HeatBuffer final : public EnergyOutput {
 public:
  void push() override { temperature_ += kHeatPerCycle; }
  i64 value() const override { return temperature_; }
  void decay() { temperature_ -= (temperature_ - kAmbient) / 32; }

 private:
  i64 temperature_ = kAmbient;
};

struct Trigger {
  u64 fired = 0;
};
// Every variant calls this on cycle finish. It costs one test unless the part is there.
inline void fireTrigger(Trigger* t) {
  if (t) ++t->fired;
}

enum class Out : uint8_t { None, Electric, Heat, Any };

struct MachineParts {
  Out out = Out::None;
  bool circuit = false;
  bool trigger = false;
  uint8_t phase = 0;  // staggers the circuit signal between machines
};

// 30% electric output, 20% heat output (exclusive: one output kind per machine),
// 25% circuit enable, 20% trigger, independent of each other.
inline MachineParts machinePartsOf(u64 seed, size_t g, int k) {
  u64 r = rnd(seed ^ 0x7632, g, R_M0 + k);
  MachineParts p;
  int o = static_cast<int>(r % 100);
  p.out = o < 30 ? Out::Electric : o < 50 ? Out::Heat : Out::None;
  p.circuit = (r >> 8) % 100 < 25;
  p.trigger = (r >> 16) % 100 < 20;
  p.phase = static_cast<uint8_t>((r >> 24) % 3);
  return p;
}

// The control behaviour holds a pointer to its entity's enable flag and is the only
// writer, so the entity update only ever reads a bool it owns.
struct ControlBehavior {
  bool* enabled;
  uint8_t phase;
};

// The passes that run outside the entity updates, identical in every v2 variant.
// Like the engine's ControlBehaviorManager, electric network and HeatBufferManager,
// they are separate loops, so their results do not depend on entity order.
struct V2Passes {
  std::vector<ControlBehavior> controls;
  std::vector<ElectricOutput*> generators;
  std::vector<HeatBuffer*> heatBuffers;
  i64 generated = 0;

  void add(const MachineParts& p, bool* enabled, EnergyOutput* out) {
    if (p.circuit) controls.push_back({enabled, p.phase});
    if (p.out == Out::Electric) generators.push_back(static_cast<ElectricOutput*>(out));
    if (p.out == Out::Heat) heatBuffers.push_back(static_cast<HeatBuffer*>(out));
  }
  // Before the entity updates. Off one period in three.
  void controlPass() {
    if (g_tick % kControlPeriod) return;
    for (ControlBehavior& c : controls) *c.enabled = (g_tick / kControlPeriod + c.phase) % 3 != 0;
  }
  // After the entity updates.
  void outputPasses() {
    for (ElectricOutput* o : generators) generated += o->drain();
    for (HeatBuffer* b : heatBuffers) b->decay();
  }
};

// v2 machines are hashed through a virtual so the checksum can walk the table
// without knowing each entity's type. It is never called on the tick path.
class HashedEntity : public Entity {
 public:
  virtual void hash(Hasher& h, Stats& s) const = 0;
};

// Same visiting order as the v1 machine hashes, then the v2 parts. An absent
// part hashes as enabled / 0 / 0, so every variant produces the same stream.
inline void hashMachineV2(Hasher& h, Stats& s, const Inventory& in, const Inventory& out, const EnergySource& energy,
                          const CraftState& cs, bool enabled, const EnergyOutput* output, const Trigger* trigger) {
  in.hash(h);
  out.hash(h);
  energy.hash(h);
  cs.hash(h);
  s.widgets += out.total(WIDGET);
  s.coalInBurners += energy.fuelCount();
  h.add(enabled);
  h.add(output ? static_cast<u64>(output->value()) : 0);
  h.add(trigger ? trigger->fired : 0);
  if (!enabled) ++s.disabledAtEnd;
  if (trigger) s.triggersFired += static_cast<i64>(trigger->fired);
}

inline std::unique_ptr<Trigger> makeTrigger(const MachineParts& p) {
  return p.trigger ? std::make_unique<Trigger>() : nullptr;
}

// The v1 workload repeats the same 10-entity pattern in every group, so a bucket
// visited in group order sees burner/electric and recipe alternate perfectly, and
// the branch predictor learns it. Splitting machines into more buckets breaks that
// pattern. Shuffling every update list gives all variants the same unpredictable
// order, closer to an active list built up over a long game.
enum class BucketOrder { Group, Shuffled };
static BucketOrder g_bucketOrder = BucketOrder::Group;

template <class T>
void shuffleBucket(std::vector<T*>& bucket, u64 seed) {
  std::mt19937_64 rng(seed ^ bucket.size());
  std::shuffle(bucket.begin(), bucket.end(), rng);
}

// Wiring, bucketing and hashing are the same in every v2 world; only `create`, the
// machine buckets (`attach`) and `tick` differ, so they live in this base.
template <class Derived>
struct V2WorldBase {
  std::vector<ElectricNetwork> nets;
  std::vector<Entity*> table;
  std::vector<Inserter*> inserters;
  V2Passes passes;
  size_t machines = 0;
  size_t G = 0;

  void build(size_t groups, u64 seed) {
    auto& self = static_cast<Derived&>(*this);
    G = groups;
    nets = makeNetworks(G);
    table.assign(G * kRoles, nullptr);
    for (size_t idx : shuffledOrder(table.size(), seed)) table[idx] = self.create(seed, idx / kRoles, idx % kRoles);
    for (size_t g = 0; g < G; ++g) {
      Entity** t = &table[g * kRoles];
      auto wire = [&](int ins, int from, int to) {
        auto* i = static_cast<Inserter*>(t[ins]);
        i->pickup = t[from];
        i->drop = t[to];
        inserters.push_back(i);
      };
      wire(R_I0, R_ORE, R_M0);
      wire(R_I1, R_M0, R_M1);
      wire(R_I2, R_M1, R_SINK);
      for (int k = 0; k < 3; ++k) self.attach(t[R_M0 + k], k, machinePartsOf(seed, g, k));
      machines += 3;
    }
    if (g_bucketOrder == BucketOrder::Shuffled) {
      shuffleBucket(inserters, seed);
      self.forEachMachineBucket([&](auto& bucket) { shuffleBucket(bucket, seed); });
    }
  }

  // Chests hash their storage inventory, which every variant's chest exposes.
  u64 checksum(Stats& s) const {
    Hasher h;
    for (const ElectricNetwork& n : nets) s.brownoutTicks += n.brownoutTicks;
    h.add(static_cast<u64>(passes.generated));
    s.energyGenerated = passes.generated;
    for (size_t g = 0; g < G; ++g) {
      Entity* const* t = &table[g * kRoles];
      for (int r = R_ORE; r <= R_FUEL; ++r) t[r]->pickupInventory()->hash(h);
      s.gearsInSinks += t[R_SINK]->pickupInventory()->total(GEAR);
      for (int r = R_I0; r <= R_I2; ++r) static_cast<Inserter*>(t[r])->hash(h);
      for (int r = R_M0; r <= R_M2; ++r) static_cast<HashedEntity*>(t[r])->hash(h, s);
    }
    return h.h;
  }
  size_t active() const { return inserters.size() + machines; }
  ~V2WorldBase() {
    for (Entity* e : table) delete e;
  }
};

// ---------------------------------------------------------------------------
// A2. STATIC with the v2 parts, as the engine would add them: every crafting
// machine carries the enable flag (the engine tests its control behaviour in
// every update), and the outputs are new hand-written types, a Generator and a
// Reactor, each with its own bucket.
// ---------------------------------------------------------------------------
namespace arch_static_v2 {

using arch_static::Container;

class CraftingMachine : public HashedEntity {
 public:
  CraftingMachine(std::unique_ptr<EnergySource> e, std::unique_ptr<Inventory> in, CraftState cs,
                  std::unique_ptr<Trigger> trigger)
      : energy_(std::move(e)),
        in_(std::move(in)),
        out_(std::make_unique<Inventory>(1)),
        trigger_(std::move(trigger)),
        cs_(cs) {}
  Inventory* pickupInventory() override { return out_.get(); }
  Inventory* dropInventory() override { return in_.get(); }
  const Recipe* dropRecipe() const override { return cs_.recipe; }
  void hash(Hasher& h, Stats& s) const override {
    hashMachineV2(h, s, *in_, *out_, *energy_, cs_, enabled, output(), trigger_.get());
  }

  bool enabled = true;

 protected:
  // Each final type passes its own finish step, so no type tests for a part it lacks.
  template <class OnFinish>
  void updateCrafting(OnFinish onFinish) {
    if (!enabled) return;
    energy_->update();
    if (craftCore<EnergySource, false>(cs_, energy_.get(), in_.get(), out_.get())) {
      fireTrigger(trigger_.get());
      onFinish();
    }
  }
  virtual const EnergyOutput* output() const { return nullptr; }

 private:
  std::unique_ptr<EnergySource> energy_;
  std::unique_ptr<Inventory> in_, out_;
  std::unique_ptr<Trigger> trigger_;
  CraftState cs_;
};

class Furnace final : public CraftingMachine {
 public:
  using CraftingMachine::CraftingMachine;
  void update() { updateCrafting([] {}); }
};
class AssemblingMachine final : public CraftingMachine {
 public:
  using CraftingMachine::CraftingMachine;
  void update() { updateCrafting([] {}); }
};

template <class Output>
class OutputMachine final : public CraftingMachine {
 public:
  OutputMachine(std::unique_ptr<EnergySource> e, std::unique_ptr<Inventory> in, CraftState cs,
                std::unique_ptr<Trigger> trigger)
      : CraftingMachine(std::move(e), std::move(in), cs, std::move(trigger)), output_(std::make_unique<Output>()) {}
  void update() { updateCrafting([this] { output_->push(); }); }
  Output* outputPart() { return output_.get(); }

 private:
  const EnergyOutput* output() const override { return output_.get(); }
  std::unique_ptr<Output> output_;
};
using Generator = OutputMachine<ElectricOutput>;
using Reactor = OutputMachine<HeatBuffer>;

struct World : V2WorldBase<World> {
  std::vector<Furnace*> furnaces;
  std::vector<AssemblingMachine*> assemblers;
  std::vector<Generator*> generators;
  std::vector<Reactor*> reactors;

  Entity* create(u64 seed, size_t g, int role) {
    ElectricNetwork* net = &nets[netOf(g, G)];
    if (role <= R_FUEL) return new Container(makeChest(role));
    if (role <= R_I2) return new Inserter(net, makeInserterState(seed, g, role - R_I0));
    int k = role - R_M0;
    MachineParts p = machinePartsOf(seed, g, k);
    auto e = makeMachineEnergy(seed, g, k, net);
    auto in = makeMachineInput(k);
    CraftState cs = makeCraftState(seed, g, k);
    if (p.out == Out::Electric) return new Generator(std::move(e), std::move(in), cs, makeTrigger(p));
    if (p.out == Out::Heat) return new Reactor(std::move(e), std::move(in), cs, makeTrigger(p));
    if (k == 0) return new Furnace(std::move(e), std::move(in), cs, makeTrigger(p));
    return new AssemblingMachine(std::move(e), std::move(in), cs, makeTrigger(p));
  }

  void attach(Entity* e, int k, const MachineParts& p) {
    auto* m = static_cast<CraftingMachine*>(e);
    EnergyOutput* out = nullptr;
    if (p.out == Out::Electric) {
      auto* gen = static_cast<Generator*>(e);
      generators.push_back(gen);
      out = gen->outputPart();
    } else if (p.out == Out::Heat) {
      auto* r = static_cast<Reactor*>(e);
      reactors.push_back(r);
      out = r->outputPart();
    } else if (k == 0) {
      furnaces.push_back(static_cast<Furnace*>(e));
    } else {
      assemblers.push_back(static_cast<AssemblingMachine*>(e));
    }
    passes.add(p, &m->enabled, out);
  }

  template <class F>
  void forEachMachineBucket(F f) {
    f(furnaces);
    f(assemblers);
    f(generators);
    f(reactors);
  }

  void tick() {
    ++g_tick;
    passes.controlPass();
    for (Inserter* e : inserters) e->Inserter::update();
    for (AssemblingMachine* e : assemblers) e->update();
    for (Furnace* e : furnaces) e->update();
    for (Generator* e : generators) e->update();
    for (Reactor* e : reactors) e->update();
    passes.outputPasses();
    for (ElectricNetwork& n : nets) n.endTick();
  }
};

}  // namespace arch_static_v2

// ---------------------------------------------------------------------------
// B2. COMPOSED with the v2 parts as more runtime slots: one class for chests and
// machines alike, every part a pointer or bit tested in every update.
// ---------------------------------------------------------------------------
namespace arch_composed_v2 {

using arch_composed::FluidBox;

class ComposedMachine final : public HashedEntity {
 public:
  enum Part : uint8_t { kInput = 1, kOutput = 2, kTimer = 4, kEnergy = 8, kFluid = 16, kCircuit = 32 };

  ComposedMachine(uint8_t parts, std::unique_ptr<EnergySource> e, std::unique_ptr<Inventory> in,
                  std::unique_ptr<Inventory> out, CraftState cs)
      : parts_(parts), energy_(std::move(e)), in_(std::move(in)), out_(std::move(out)), cs_(cs) {}

  bool ticks() const { return parts_ & (kTimer | kEnergy | kFluid); }

  void update() {
    if ((parts_ & kCircuit) && !enabled) return;
    if (energy_) energy_->update();
    bool finished = (parts_ & kTimer) && craftCore<EnergySource, true>(cs_, energy_.get(), in_.get(), out_.get());
    if (fluid_) fluid_->update();
    if (electric && finished) electric->push();
    if (heat && finished) heat->push();
    if (finished) fireTrigger(trigger.get());
  }

  Inventory* pickupInventory() override { return out_.get(); }
  Inventory* dropInventory() override { return in_ ? in_.get() : out_.get(); }
  const Recipe* dropRecipe() const override { return (parts_ & kTimer) ? cs_.recipe : nullptr; }

  void hash(Hasher& h, Stats& s) const override {
    const EnergyOutput* output = electric ? static_cast<const EnergyOutput*>(electric.get()) : heat.get();
    hashMachineV2(h, s, *in_, *out_, *energy_, cs_, enabled, output, trigger.get());
  }

  bool enabled = true;
  std::unique_ptr<ElectricOutput> electric;
  std::unique_ptr<HeatBuffer> heat;
  std::unique_ptr<Trigger> trigger;

 private:
  uint8_t parts_;
  std::unique_ptr<EnergySource> energy_;
  std::unique_ptr<Inventory> in_, out_;
  std::unique_ptr<FluidBox> fluid_;
  CraftState cs_;
};

struct World : V2WorldBase<World> {
  std::vector<ComposedMachine*> composed;

  Entity* create(u64 seed, size_t g, int role) {
    using CM = ComposedMachine;
    ElectricNetwork* net = &nets[netOf(g, G)];
    if (role <= R_FUEL) return new CM(CM::kOutput, nullptr, nullptr, makeChest(role), CraftState{});
    if (role <= R_I2) return new Inserter(net, makeInserterState(seed, g, role - R_I0));
    int k = role - R_M0;
    MachineParts p = machinePartsOf(seed, g, k);
    uint8_t parts = CM::kInput | CM::kOutput | CM::kTimer | CM::kEnergy | (p.circuit ? CM::kCircuit : 0);
    auto* m = new CM(parts, makeMachineEnergy(seed, g, k, net), makeMachineInput(k), std::make_unique<Inventory>(1),
                     makeCraftState(seed, g, k));
    if (p.out == Out::Electric) m->electric = std::make_unique<ElectricOutput>();
    if (p.out == Out::Heat) m->heat = std::make_unique<HeatBuffer>();
    m->trigger = makeTrigger(p);
    return m;
  }

  void attach(Entity* e, int /*k*/, const MachineParts& p) {
    auto* m = static_cast<ComposedMachine*>(e);
    composed.push_back(m);
    EnergyOutput* out = m->electric ? static_cast<EnergyOutput*>(m->electric.get()) : m->heat.get();
    passes.add(p, &m->enabled, out);
  }

  template <class F>
  void forEachMachineBucket(F f) {
    f(composed);
  }

  void tick() {
    ++g_tick;
    passes.controlPass();
    for (Inserter* e : inserters) e->Inserter::update();
    for (ComposedMachine* e : composed) e->update();
    passes.outputPasses();
    for (ElectricNetwork& n : nets) n.endTick();
  }
};

}  // namespace arch_composed_v2

// ---------------------------------------------------------------------------
// D1 and D2. TEMPLATED COMPOSED with the v2 parts. The energy output kind and
// the circuit enable become two more template parameters. D2 instantiates one
// shape per combination the workload uses, each with its own bucket; D1 uses the
// single v1 machine shape with the output behind one pointer (Out::Any, tested
// only on cycle finish) and the enable flag always present (tested once per
// update). D2n is D2 with the accessor functions copied into every shape, which
// is what a template produces by default (see ComposedCore).
// ---------------------------------------------------------------------------
namespace arch_templated_v2 {

using arch_templated::EnergyPart;
using arch_templated::FluidPart;
using arch_templated::InputPart;
using arch_templated::NoEnergy;
using arch_templated::TimerPart;

template <Out> struct OutputPart {};
template <> struct OutputPart<Out::Electric> { std::unique_ptr<ElectricOutput> output; };
template <> struct OutputPart<Out::Heat> { std::unique_ptr<HeatBuffer> output; };
template <> struct OutputPart<Out::Any> { std::unique_ptr<EnergyOutput> output; };
template <bool> struct CircuitPart {};
template <> struct CircuitPart<true> { bool enabled = true; };

// The functions other entities call through (inserters ask any entity for its
// inventories and recipe) live in this core, which is instantiated once per v1
// shape. A call site in the inserter is indirect, and its prediction depends on
// how many distinct function addresses it sees, not on how many vtables: if every
// v2 shape had its own copy of these accessors, the inserter's calls would go from
// one target to six. kInterfaceCopy exists to measure exactly that (variant D2n):
// shapes with the same value share one copy.
template <bool Input, bool Energy, bool Timer, bool Fluid, int kInterfaceCopy>
class ComposedCore : public HashedEntity,
                     public InputPart<Input>,
                     public EnergyPart<Energy>,
                     public TimerPart<Timer>,
                     public FluidPart<Fluid> {
 public:
  explicit ComposedCore(std::unique_ptr<Inventory> out) : out_(std::move(out)) {}

  Inventory* pickupInventory() override { return out_.get(); }
  Inventory* dropInventory() override {
    if constexpr (Input) return this->in.get();
    return out_.get();
  }
  const Recipe* dropRecipe() const override {
    if constexpr (Timer) return this->cs.recipe;
    return nullptr;
  }

 protected:
  std::unique_ptr<Inventory> out_;
};

template <bool Input, bool Energy, bool Timer, bool Fluid, Out kOut, bool Circuit, bool kSharedInterface = true>
class Composed final
    : public ComposedCore<Input, Energy, Timer, Fluid, kSharedInterface ? 0 : 1 + 2 * static_cast<int>(kOut) + Circuit>,
      public OutputPart<kOut>,
      public CircuitPart<Circuit> {
  using Core = ComposedCore<Input, Energy, Timer, Fluid, kSharedInterface ? 0 : 1 + 2 * static_cast<int>(kOut) + Circuit>;

 public:
  static constexpr Out kOutput = kOut;

  using Core::Core;

  void update() {
    if constexpr (Circuit) {
      if (!this->enabled) return;
    }
    if constexpr (Energy) this->energy->update();
    if constexpr (Timer) {
      if (craft()) finish();
    }
    if constexpr (Fluid) this->fluid->update();
  }

  void hash(Hasher& h, Stats& s) const override {
    static_assert(Input && Energy && Timer, "only crafting shapes are hashed through HashedEntity");
    hashMachineV2(h, s, *this->in, *this->out_, *this->energy, this->cs, isEnabled(), outputPart(), trigger.get());
  }

  bool* enabledFlag() {
    if constexpr (Circuit) return &this->enabled;
    return nullptr;
  }
  EnergyOutput* outputPart() const {
    if constexpr (kOut != Out::None) return this->output.get();
    return nullptr;
  }

  std::unique_ptr<Trigger> trigger;  // not a shape axis: it never ticks, only fires on finish

 private:
  bool craft() {
    Inventory* in = nullptr;
    if constexpr (Input) in = this->in.get();
    if constexpr (Energy) {
      return craftCore<EnergySource, false>(this->cs, this->energy.get(), in, this->out_.get());
    } else {
      NoEnergy free;
      return craftCore<NoEnergy, false>(this->cs, &free, in, this->out_.get());
    }
  }
  void finish() {
    fireTrigger(trigger.get());
    if constexpr (kOut == Out::Any) {
      if (this->output) this->output->push();
    } else if constexpr (kOut != Out::None) {
      this->output->push();
    }
  }
  bool isEnabled() const {
    if constexpr (Circuit) return this->enabled;
    return true;
  }
};

using arch_templated::ChestShape;
template <Out kOut, bool Circuit, bool kShared = true>
using MachineShape = Composed<true, true, true, false, kOut, Circuit, kShared>;

// D1's single ticking shape.
using AnyMachine = MachineShape<Out::Any, true>;

template <class Shape>
Shape* makeMachine(u64 seed, size_t g, int k, ElectricNetwork* net, const MachineParts& p) {
  auto* m = new Shape(std::make_unique<Inventory>(1));
  m->energy = makeMachineEnergy(seed, g, k, net);
  m->in = makeMachineInput(k);
  m->cs = makeCraftState(seed, g, k);
  if constexpr (Shape::kOutput == Out::Electric) m->output = std::make_unique<ElectricOutput>();
  if constexpr (Shape::kOutput == Out::Heat) m->output = std::make_unique<HeatBuffer>();
  if constexpr (Shape::kOutput == Out::Any) {
    if (p.out == Out::Electric) m->output = std::make_unique<ElectricOutput>();
    if (p.out == Out::Heat) m->output = std::make_unique<HeatBuffer>();
  }
  m->trigger = makeTrigger(p);
  return m;
}

// The six ticking shapes D2 instantiates: three output kinds times circuit on/off.
template <bool kShared>
struct WorldD2T : V2WorldBase<WorldD2T<kShared>> {
  using Plain = MachineShape<Out::None, false, kShared>;
  using PlainCircuit = MachineShape<Out::None, true, kShared>;
  using Generator = MachineShape<Out::Electric, false, kShared>;
  using GeneratorCircuit = MachineShape<Out::Electric, true, kShared>;
  using Reactor = MachineShape<Out::Heat, false, kShared>;
  using ReactorCircuit = MachineShape<Out::Heat, true, kShared>;

  std::vector<Plain*> plain;
  std::vector<PlainCircuit*> plainCircuit;
  std::vector<Generator*> generators;
  std::vector<GeneratorCircuit*> generatorsCircuit;
  std::vector<Reactor*> reactors;
  std::vector<ReactorCircuit*> reactorsCircuit;

  // Picks the shape once, at construction, from the parts the prototype declares.
  Entity* create(u64 seed, size_t g, int role) {
    ElectricNetwork* net = &this->nets[netOf(g, this->G)];
    if (role <= R_FUEL) return new ChestShape(makeChest(role));
    if (role <= R_I2) return new Inserter(net, makeInserterState(seed, g, role - R_I0));
    int k = role - R_M0;
    MachineParts p = machinePartsOf(seed, g, k);
    switch (p.out) {
      case Out::Electric:
        return p.circuit ? static_cast<Entity*>(makeMachine<GeneratorCircuit>(seed, g, k, net, p))
                         : makeMachine<Generator>(seed, g, k, net, p);
      case Out::Heat:
        return p.circuit ? static_cast<Entity*>(makeMachine<ReactorCircuit>(seed, g, k, net, p))
                         : makeMachine<Reactor>(seed, g, k, net, p);
      default:
        return p.circuit ? static_cast<Entity*>(makeMachine<PlainCircuit>(seed, g, k, net, p))
                         : makeMachine<Plain>(seed, g, k, net, p);
    }
  }

  template <class Shape>
  void addTo(std::vector<Shape*>& bucket, Entity* e, const MachineParts& p) {
    auto* m = static_cast<Shape*>(e);
    bucket.push_back(m);
    this->passes.add(p, m->enabledFlag(), m->outputPart());
  }

  void attach(Entity* e, int /*k*/, const MachineParts& p) {
    switch (p.out) {
      case Out::Electric:
        return p.circuit ? addTo(generatorsCircuit, e, p) : addTo(generators, e, p);
      case Out::Heat:
        return p.circuit ? addTo(reactorsCircuit, e, p) : addTo(reactors, e, p);
      default:
        return p.circuit ? addTo(plainCircuit, e, p) : addTo(plain, e, p);
    }
  }

  template <class F>
  void forEachMachineBucket(F f) {
    f(plain);
    f(plainCircuit);
    f(generators);
    f(generatorsCircuit);
    f(reactors);
    f(reactorsCircuit);
  }

  void tick() {
    ++g_tick;
    this->passes.controlPass();
    for (Inserter* e : this->inserters) e->Inserter::update();
    for (Plain* e : plain) e->update();
    for (PlainCircuit* e : plainCircuit) e->update();
    for (Generator* e : generators) e->update();
    for (GeneratorCircuit* e : generatorsCircuit) e->update();
    for (Reactor* e : reactors) e->update();
    for (ReactorCircuit* e : reactorsCircuit) e->update();
    this->passes.outputPasses();
    for (ElectricNetwork& n : this->nets) n.endTick();
  }
};
using WorldD2 = WorldD2T<true>;
using WorldD2n = WorldD2T<false>;

// kSortByShape is a control, not a design: D1's code with its one bucket visited
// in the order D2's six buckets would visit the same machines. It separates the
// cost of a different visiting order from the cost of more shapes.
template <bool kSortByShape>
struct WorldD1T : V2WorldBase<WorldD1T<kSortByShape>> {
  using Base = V2WorldBase<WorldD1T<kSortByShape>>;
  std::vector<AnyMachine*> machinesBucket;
  std::vector<int> shapeKey;

  Entity* create(u64 seed, size_t g, int role) {
    ElectricNetwork* net = &this->nets[netOf(g, this->G)];
    if (role <= R_FUEL) return new ChestShape(makeChest(role));
    if (role <= R_I2) return new Inserter(net, makeInserterState(seed, g, role - R_I0));
    int k = role - R_M0;
    return makeMachine<AnyMachine>(seed, g, k, net, machinePartsOf(seed, g, k));
  }

  void attach(Entity* e, int /*k*/, const MachineParts& p) {
    auto* m = static_cast<AnyMachine*>(e);
    machinesBucket.push_back(m);
    shapeKey.push_back(static_cast<int>(p.out) * 2 + p.circuit);
    this->passes.add(p, m->enabledFlag(), m->outputPart());
  }

  template <class F>
  void forEachMachineBucket(F f) {
    f(machinesBucket);
  }

  void build(size_t groups, u64 seed) {
    Base::build(groups, seed);
    if constexpr (kSortByShape) {
      std::vector<size_t> idx(machinesBucket.size());
      std::iota(idx.begin(), idx.end(), size_t{0});
      std::stable_sort(idx.begin(), idx.end(), [&](size_t a, size_t b) { return shapeKey[a] < shapeKey[b]; });
      std::vector<AnyMachine*> sorted;
      for (size_t i : idx) sorted.push_back(machinesBucket[i]);
      machinesBucket.swap(sorted);
    }
  }

  void tick() {
    ++g_tick;
    this->passes.controlPass();
    for (Inserter* e : this->inserters) e->Inserter::update();
    for (AnyMachine* e : machinesBucket) e->update();
    this->passes.outputPasses();
    for (ElectricNetwork& n : this->nets) n.endTick();
  }
};
using WorldD1 = WorldD1T<false>;
using WorldD1Sorted = WorldD1T<true>;

}  // namespace arch_templated_v2

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
struct RunResult {
  double nsPerTick;
  u64 checksum;
  size_t active;
  Stats stats;
};

template <class W>
RunResult runOnce(size_t groups, u64 seed, int warm, int ticks) {
  auto w = std::make_unique<W>();
  w->build(groups, seed);
  g_tick = 1;  // slot stamps start at 0, so tick 1 sees every preload as old
  for (int i = 0; i < warm; ++i) w->tick();
  auto t0 = std::chrono::steady_clock::now();
  for (int i = 0; i < ticks; ++i) w->tick();
  auto t1 = std::chrono::steady_clock::now();
  RunResult r{};
  r.nsPerTick = std::chrono::duration<double, std::nano>(t1 - t0).count() / ticks;
  r.checksum = w->checksum(r.stats);
  r.active = w->active();
  return r;
}

static double median(std::vector<double> v) {
  std::sort(v.begin(), v.end());
  size_t n = v.size();
  return n % 2 ? v[n / 2] : 0.5 * (v[n / 2 - 1] + v[n / 2]);
}

struct Variant {
  const char* name;
  RunResult (*run)(size_t groups, u64 seed, int warm, int ticks);
};

struct Options {
  int warm = 60, ticks = 600, repeats = 3;
  u64 seed = 12345;
};

// Variants run in turn inside each repeat, so slow drift in machine load hits all
// of them alike. The first variant is the baseline for the ratios and the checksum.
static bool runSuite(const char* title, const std::vector<Variant>& vs, const std::vector<size_t>& sizes,
                     const Options& o, bool v2) {
  std::printf("== %s workload: warm-up %d ticks, measured %d ticks, %d repeats ==\n", title, o.warm, o.ticks, o.repeats);
  std::printf("%-9s %-10s %7s %12s %12s %10s %10s %18s\n", "N", "arch", "active", "min ns/tick", "med ns/tick",
              "min ns/e-t", "med ns/e-t", "checksum");
  const size_t nv = vs.size();
  bool allMatch = true;
  for (size_t N : sizes) {
    size_t G = N / kRoles;
    std::vector<std::vector<double>> t(nv);
    std::vector<u64> sums(nv);
    std::vector<size_t> act(nv);
    u64 reference = 0;
    Stats st{};
    for (int r = 0; r < o.repeats; ++r) {
      for (size_t a = 0; a < nv; ++a) {
        RunResult res = vs[a].run(G, o.seed, o.warm, o.ticks);
        if (r == 0 && a == 0) reference = res.checksum;
        if (res.checksum != reference) allMatch = false;
        t[a].push_back(res.nsPerTick);
        sums[a] = res.checksum;
        act[a] = res.active;
        if (a == 0) st = res.stats;
      }
    }
    std::vector<double> mn(nv), md(nv);
    for (size_t a = 0; a < nv; ++a) {
      mn[a] = *std::min_element(t[a].begin(), t[a].end());
      md[a] = median(t[a]);
      std::printf("%-9zu %-10s %7zu %12.0f %12.0f %10.2f %10.2f %016llx\n", G * kRoles, vs[a].name, act[a], mn[a], md[a],
                  mn[a] / (G * kRoles), md[a] / (G * kRoles), static_cast<unsigned long long>(sums[a]));
    }
    for (size_t a = 1; a < nv; ++a)
      std::printf("          ratio %s/%s: min %.3f  median %.3f\n", vs[a].name, vs[0].name, mn[a] / mn[0], md[a] / md[0]);
    std::printf("          workload: %lld gears in sinks, %lld widgets made, %lld coal left in burners, %lld network-ticks in brownout\n",
                static_cast<long long>(st.gearsInSinks), static_cast<long long>(st.widgets),
                static_cast<long long>(st.coalInBurners), static_cast<long long>(st.brownoutTicks));
    if (v2)
      std::printf("          v2 parts: %lld J drained from generators, %lld triggers fired, %lld machines disabled at the end\n",
                  static_cast<long long>(st.energyGenerated), static_cast<long long>(st.triggersFired),
                  static_cast<long long>(st.disabledAtEnd));
    std::printf("\n");
  }
  std::printf("checksums %s across all %s variants and repeats\n\n", allMatch ? "MATCH" : "DIFFER", title);
  return allMatch;
}

static void printSizes() {
  namespace tv2 = arch_templated_v2;
  std::printf("sizeof, v1 workload\n");
  std::printf("  chest:   A Container %zu, B ComposedMachine %zu, D Composed<chest> %zu\n", sizeof(arch_static::Container),
              sizeof(arch_composed::ComposedMachine), sizeof(arch_templated::ChestShape));
  std::printf("  machine: A Furnace/AssemblingMachine %zu/%zu, B ComposedMachine %zu, D Composed<machine> %zu\n",
              sizeof(arch_static::Furnace), sizeof(arch_static::AssemblingMachine), sizeof(arch_composed::ComposedMachine),
              sizeof(arch_templated::MachineShape));
  std::printf("sizeof, v2 workload\n");
  std::printf("  chest:   A2 Container %zu, B2 ComposedMachine %zu, D1/D2 Composed<chest> %zu\n", sizeof(arch_static::Container),
              sizeof(arch_composed_v2::ComposedMachine), sizeof(tv2::ChestShape));
  std::printf("  A2:      Furnace %zu, AssemblingMachine %zu, Generator %zu, Reactor %zu\n", sizeof(arch_static_v2::Furnace),
              sizeof(arch_static_v2::AssemblingMachine), sizeof(arch_static_v2::Generator), sizeof(arch_static_v2::Reactor));
  std::printf("  B2:      ComposedMachine %zu (every shape)\n", sizeof(arch_composed_v2::ComposedMachine));
  std::printf("  D1:      Composed<machine, out=any, circuit> %zu\n", sizeof(tv2::AnyMachine));
  using D2 = tv2::WorldD2;
  std::printf("  D2:      plain %zu, plain+circuit %zu, generator %zu, generator+circuit %zu, reactor %zu, reactor+circuit %zu\n\n",
              sizeof(D2::Plain), sizeof(D2::PlainCircuit), sizeof(D2::Generator), sizeof(D2::GeneratorCircuit),
              sizeof(D2::Reactor), sizeof(D2::ReactorCircuit));
}

static bool listed(const std::string& list, const std::string& name) {
  std::string padded = "," + list + ",";
  return padded.find("," + name + ",") != std::string::npos;
}

int main(int argc, char** argv) {
  std::vector<size_t> sizes;
  Options o;
  std::string suites = "v1,v2,v2s", only;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a == "--ticks" && i + 1 < argc) o.ticks = std::atoi(argv[++i]);
    else if (a == "--warm" && i + 1 < argc) o.warm = std::atoi(argv[++i]);
    else if (a == "--repeats" && i + 1 < argc) o.repeats = std::atoi(argv[++i]);
    else if (a == "--seed" && i + 1 < argc) o.seed = std::strtoull(argv[++i], nullptr, 10);
    else if (a == "--suite" && i + 1 < argc) suites = argv[++i];
    else if (a == "--only" && i + 1 < argc) only = argv[++i];
    else sizes.push_back(std::strtoull(a.c_str(), nullptr, 10));
  }
  if (sizes.empty()) sizes = {10'000, 100'000, 1'000'000};

  // The first variant of each suite is its baseline; --only keeps it regardless.
  auto pick = [&](std::vector<Variant> vs) {
    std::vector<Variant> kept{vs[0]};
    for (size_t i = 1; i < vs.size(); ++i)
      if (only.empty() || listed(only, vs[i].name)) kept.push_back(vs[i]);
    return kept;
  };

  printSizes();
  bool ok = true;
  if (listed(suites, "v1")) {
    g_bucketOrder = BucketOrder::Group;
    ok &= runSuite("v1",
                   pick({{"A", runOnce<arch_static::World>},
                         {"B", runOnce<arch_composed::World>},
                         {"C", runOnce<arch_ecs::World>},
                         {"D", runOnce<arch_templated::World>}}),
                   sizes, o, false);
  }
  if (listed(suites, "v2")) {
    g_bucketOrder = BucketOrder::Group;
    ok &= runSuite("v2 (group order)",
                   pick({{"A2", runOnce<arch_static_v2::World>},
                         {"B2", runOnce<arch_composed_v2::World>},
                         {"D1", runOnce<arch_templated_v2::WorldD1>},
                         {"D2", runOnce<arch_templated_v2::WorldD2>},
                         {"D2n", runOnce<arch_templated_v2::WorldD2n>},
                         {"D1s", runOnce<arch_templated_v2::WorldD1Sorted>}}),
                   sizes, o, true);
  }
  if (listed(suites, "v2s")) {
    g_bucketOrder = BucketOrder::Shuffled;
    ok &= runSuite("v2 (shuffled order)",
                   pick({{"A2", runOnce<arch_static_v2::World>},
                         {"B2", runOnce<arch_composed_v2::World>},
                         {"D1", runOnce<arch_templated_v2::WorldD1>},
                         {"D2", runOnce<arch_templated_v2::WorldD2>},
                         {"D2n", runOnce<arch_templated_v2::WorldD2n>}}),
                   sizes, o, true);
  }
  return ok ? 0 : 1;
}
