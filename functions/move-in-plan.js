export function moveInPlan(agreement, configuration) {
  const fromType = String(agreement.propertyDetails?.rooms ?? '').match(/^([1-4](?:\.5)?)\+? BHK$/)?.[1];
  const bedrooms = configuration?.bedrooms ?? (fromType ? Math.ceil(Number(fromType)) : agreement.propertyDetails?.rooms === '1 RK' ? 0 : null);
  if (!Number.isInteger(bedrooms) || bedrooms < 0 || bedrooms > 9) return [];
  const washrooms = configuration?.washrooms ?? Math.max(1, bedrooms);
  const definitions = [
    ['Living room', ['Entrance door', 'Door lock', 'Walls', 'Ceiling', 'Floor', 'Windows', 'Lights', 'Switches', 'Fans', 'Living room overview']],
    ['Kitchen', ['Kitchen overview', 'Walls', 'Floor', 'Countertop', 'Sink', 'Sink tap', 'Under-sink pipes', 'Cabinets', 'Chimney', 'Stove area', 'Window', 'Sockets']],
    ...Array.from({ length: bedrooms }, (_, index) => [`Bedroom ${index + 1}`, ['Room overview', 'Door and lock', 'Walls', 'Ceiling', 'Floor', 'Window', 'Lights and switches', 'Wardrobe', ...(index === 0 ? ['Fan'] : [])]]),
    ...Array.from({ length: washrooms }, (_, index) => [`Washroom ${index + 1}`, ['Room overview', 'Door and lock', 'Walls and floor', 'Wash basin', 'Taps and shower', 'Toilet', 'Drain and pipes', ...(index === 0 ? ['Geyser'] : [])]]),
    ...(configuration?.balcony === false ? [] : [['Balcony / utility', ['Overview', 'Floor', 'Railing', 'Drain']]]),
    ['Fixtures & fittings', ['Main locks', 'Intercom', 'Electrical panel', 'Water connections', 'Parking access', 'Other fixtures']],
  ];
  return definitions.map(([room, titles], roomIndex) => ({ room, items: titles.map((title, itemIndex) => ({
    id: `room-${roomIndex}-item-${itemIndex}`, title,
    optional: ['Wardrobe', 'Fan', 'Fans', 'Chimney', 'Geyser', 'Intercom', 'Parking access', 'Other fixtures', 'Stove area'].includes(title),
  })) }));
}
